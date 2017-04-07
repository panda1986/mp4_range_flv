package mp4
{
    import flash.utils.ByteArray;

    public class MP4
    {
        private var _mux:Muxer
        
        public var moov_start:uint
        public var moov_end:uint
        
        public function MP4()
        {
            _mux = new Muxer()    
        }
        
        public function parse_moov_size(data:ByteArray):void {
            data.position = 0
            //get moov box
            while (data.bytesAvailable > 8)
            {
                var parentBox:Box = new Box(0);
                var level_box:Box = parentBox.discovery(data);
                if (level_box) {
                    if (level_box.type == BaseMP4.SrsMp4BoxTypeMOOV) {
                        moov_start = level_box.position;
                        moov_end = level_box.position + level_box.size - 1;    
                        break;
                    }
                    data.position = level_box.position + level_box.size;
                } else {
                    break;
                }
            }
            return
        }
        
        public function parse_moov(data:ByteArray):void {
            data.position = 0
            //parse moov box
            while (data.bytesAvailable > 8)
            {
                var parentBox:Box = new Box(0);
                var level_box:Box = parentBox.discovery(data);
                if (level_box) {
                    var d:ByteArray = new ByteArray();
                    d.writeBytes(data, level_box.position + level_box.offset, level_box.size - level_box.offset);
                    d.position = 0;
                    level_box.decode_header(d);
                    level_box.decode_boxes(d);
                    data.position = level_box.position + level_box.size;
                    
                    if (level_box.type == BaseMP4.SrsMp4BoxTypeMOOV) {
                        _mux.parse_moov(MoovBox(level_box))
                        break;
                    }
                } else {
                    break;
                }
            }
            return    
        }
        
        public function parse_sequence_header():ByteArray {
            return _mux.parse_sequence_header()    
        }
        
        public function parse_piece_range(piece_id:uint):Object {
            return _mux.dec.parse_piece_range(piece_id)
        }
        
        public function parse_piece(data:ByteArray, start_sid:uint, end_sid:uint):ByteArray {
            return _mux.parse_piece(data, start_sid, end_sid);
        }
        
        public function get_sample_offset(id:uint):uint {
            return _mux.dec.samples.get_offset(id)
        }
    }
}

class SrsFlvTag {
    public var tag_type:uint
    public var time:uint
    public var data:ByteArray
    public function SrsFlvTag() {
        data = new ByteArray()
    }
}

class Muxer {
    public var dec:Decoder
    
    public function Muxer() {
        dec = new Decoder()
    }
    
    public function mux():void {
        
    }
    
    public function parse_piece(data:ByteArray, start_sid:uint, end_sid:uint):ByteArray {
        data.position = 0;
        var res:ByteArray = new ByteArray()
        var relative_offset:uint = dec.samples.get_offset(start_sid);    
        for (var i:uint = start_sid; i < end_sid; i++) {
            var s:SrsMp4Sample = dec.read_sample(i, data, relative_offset);
            if (s) {
                var t:SrsFlvTag = sample_to_tag(s)
                this.write_flv_tag(res, t)
            }
        }
        
        return res
    }
    
    public function parse_sequence_header():ByteArray {
        var sh:ByteArray = new ByteArray()
        // FLV Header    
        sh.writeUTFBytes("FLV")
        sh.writeByte(1)
        
        var flag:int = 0
        if (dec.acodec != 0) {
            flag = flag | 0x04
        }
        if (dec.vcodec != 0) {
            flag = flag | 0x01
        }
        sh.writeByte(flag)
        
        var dataOffset:uint = 9
        sh.writeUnsignedInt(dataOffset)
        sh.writeUnsignedInt(0)    // first prev tag size
        
        // FLV metadata tag, type=18
        sh.writeByte(18)
        
        // datasize 3 bytes    
        var meta:ByteArray = encode_metadata()
        this.write_3_bytes(sh, meta.length)
        // timestamp 4 bytes    
        sh.writeUnsignedInt(0)
        // streamId 3 bytes    
        this.write_3_bytes(sh, 0)
        // write meta
        sh.writeBytes(meta)
        // prev tag size    
        sh.writeUnsignedInt(meta.length + 11)  
            
        // video sh
        var s:SrsMp4Sample = dec.read_video_sh_sample()
        if (!s) {
            trace("have no video sh")
            return sh
        }
        var t:SrsFlvTag = sample_to_tag(s)    
        this.write_flv_tag(sh, t)    
        // audio sh 
        s = dec.read_audio_sh_sample()
        if (!s) {
            trace("have no audio sh")
            return sh
        }
        t = sample_to_tag(s)    
        this.write_flv_tag(sh, t)     
        return sh    
    }
    
    public function parse_moov(moov:MoovBox):void {
        dec.parse_moov(moov)
    }
    
    private function write_3_bytes(data:ByteArray, value:uint):void {
        var tmp:ByteArray = new ByteArray()
        tmp.writeUnsignedInt(value)
        data.writeBytes(tmp, 1, 3)    
    }
    
    private function encode_metadata():ByteArray {
        var meta:ByteArray = new ByteArray()
        this.put_amf_string(meta, "onMetaData") 
        
        meta.writeByte(BaseMP4.AMF_DATA_TYPE_ECMA_array)
        meta.writeUnsignedInt(8)
        this.put_amf_string_data(meta, "duration")
        this.put_amf_double(meta, this.dec.duration / 1000)
        this.put_amf_string_data(meta, "width")
        this.put_amf_double(meta, Number(this.dec.width))
        this.put_amf_string_data(meta, "height")
        this.put_amf_double(meta, Number(this.dec.height))
        this.put_amf_string_data(meta, "videocodecid")
        this.put_amf_double(meta, Number(this.dec.vcodec)) 
        this.put_amf_string_data(meta, "audiosamplerate")
        var sr:int = this.human_read_audio_samplerate(this.dec.sample_rate)    
        this.put_amf_double(meta, Number(sr))
        
        this.put_amf_string_data(meta, "author")
        this.put_amf_string(meta, "panda-mengxiaowei@bravocloud.com")
        
        this.put_amf_string_data(meta, "audiosamplesize")
        var sb:int = this.human_read_soundbits(this.dec.sample_size)
        this.put_amf_double(meta, Number(sb))
        
        this.put_amf_string_data(meta, "audiocodecid")
        this.put_amf_double(meta, Number(this.dec.acodec))    
        
        meta.position = 0    
        return meta
    }
    
    private function put_amf_double(byte:ByteArray, data:Number):void {
        byte.writeByte(BaseMP4.AMF_DATA_TYPE_NUMBER)
        byte.writeDouble(data)   
    }
    
    private function put_amf_string(byte:ByteArray, data:String):void {
        byte.writeByte(BaseMP4.AMF_DATA_TYPE_STRING)
        this.put_amf_string_data(byte, data)    
    }
    
    private function put_amf_string_data(byte:ByteArray, data:String):void {
        byte.writeShort(data.length)
        byte.writeUTFBytes(data)    
    }
    
    private function human_read_audio_samplerate(sample_rate:int):int {
        switch (sample_rate)
        {
            case 0:
                return 5512
            case 1:
                return 11025
            case 2:
                return 22050
            case 3:
                return 44100
        }
        return 0    
    }
    
    private function human_read_soundbits(soundbits:int):int {
        switch (soundbits) {
            case 0:
                return 8
            case 1:
                return 16
        }
        return 0
    }
    
    private function write_flv_tag(flv:ByteArray, t:SrsFlvTag):void {
        flv.writeByte(t.tag_type)
        this.write_3_bytes(flv, t.data.length)
        this.write_3_bytes(flv, t.time)
        flv.writeByte(0)
        this.write_3_bytes(flv, 0)
        flv.writeBytes(t.data)  
        flv.writeUnsignedInt(t.data.length + 11)
    }
    
    private function sample_to_tag(s:SrsMp4Sample):SrsFlvTag {
        var tag:SrsFlvTag = new SrsFlvTag()
        
        tag.time = s.dts
        if (s.handler_type == BaseMP4.SrsMp4HandlerTypeSOUN) {
            tag.tag_type = BaseMP4.SRS_RTMP_TYPE_AUDIO
            // E.4.2.1 AUDIODATA, flv_v10_1.pdf, page 3
            var tmp:uint = s.codec << 4 | s.sample_rate << 2 | s.sound_bits << 1 | s.channels  
            tag.data.writeByte(tmp) 
            
            if (s.codec == BaseMP4.SrsAudioCodecIdAAC) {
                if (s.frame_trait == BaseMP4.SrsAudioAacFrameTraitSequenceHeader) {
                    tag.data.writeByte(0)
                } else {
                    tag.data.writeByte(1)
                }
            }
            tag.data.writeBytes(s.sample)
            return tag    
        }
        
        // E.4.3.1 VIDEODATA, flv_v10_1.pdf, page 5
        tmp = s.frame_ype << 4 | s.codec
        tag.data.writeByte(tmp)
        if (s.codec == BaseMP4.SrsVideoCodecIdAVC) {
            tag.tag_type = BaseMP4.SRS_RTMP_TYPE_VIDEO
            if (s.frame_trait == BaseMP4.SrsVideoAvcFrameTraitSequenceHeader) {
                tag.data.writeByte(0)
            } else {
                tag.data.writeByte(1)
            }
            
            // cts = pts - dts, where dts = flvheader->timestamp.
            var cts:int = s.pts - s.dts // TODO: may be cts = (s.pts - s.dts) /90;
            this.write_3_bytes(tag.data, cts)   
        }
        tag.data.writeBytes(s.sample)
        tag.data.position = 0    
        return tag
    }
}

class SrsMp4Sample {
    // The handler type, it's SrsMp4HandlerType.
    public var handler_type:uint
    // The dts in milliseconds.
    public var dts:uint
    // The codec id.
    //      video: SrsVideoCodecId.
    //      audio: SrsAudioCodecId.
    public var codec:uint //16
    // The frame trait, some characteristic:
    //      video: SrsVideoAvcFrameTrait.
    //      audio: SrsAudioAacFrameTrait.
    public var frame_trait:uint //16
    
    // The video pts in milliseconds. Ignore for audio.
    public var pts:uint
    // The video frame type, it's SrsVideoAvcFrameType.
    public var frame_ype:uint //16
    
    // The audio sample rate, it's SrsAudioSampleRate.
    public var sample_rate:uint //8
    // The audio sound bits, it's SrsAudioSampleBits.
    public var sound_bits:uint //8
    // The audio sound type, it's SrsAudioChannels.
    public var channels:uint //8
    
    // The size of sample payload in bytes.
    public var nb_sample:uint
    // The output sample data, user must free it by srs_mp4_free_sample.
    public var sample:ByteArray
    
    public function SrsMp4Sample() {
        sample = new ByteArray()
    }
    
    public function size():uint {
        if (this.handler_type == BaseMP4.SrsMp4HandlerTypeSOUN) {
            if (this.codec == BaseMP4.SrsAudioCodecIdAAC) {
                return this.nb_sample + 2
            }
            return this.nb_sample + 1
        }
        if (this.codec == BaseMP4.SrsVideoCodecIdAVC) {
            return this.nb_sample + 5
        }
        return this.nb_sample + 1
    }
    
    public function string():String {
        return "sample--ht:" + this.handler_type + ", dts:" + this.dts + ", codec:" + this.codec + ", frameType:" + this.frame_ype + ", sampe rate:" + this.sample_rate + ", sound bits:" + this.sound_bits + ", channels:" + this.channels + ", nb:" + this.nb_sample
    }
}

class Decoder {
    public var samples:Mp4SampleManager
    // The current written sample information.
    private var curIndex:uint
    
    // The video codec of first track, generally there is zero or one track.
    // Forbidden if no video stream.
    // TODO: FIXME: Use SrsFormat instead.
    public var vcodec:uint
    public var duration:Number
    public var width:uint
    public var height:uint
    
    // For H.264/AVC, the avcc contains the sps/pps.
    public var pavcc:ByteArray
    // Whether avcc is written to reader.
    public var avccWritten:Boolean
    
    // The audio codec of first track, generally there is zero or one track.
    // Forbidden if no audio stream.
    public var acodec:uint
    public var sample_rate:uint
    public var sample_size:uint
    public var channels:uint
    
    // For AAC, the asc in esds box.
    public var pasc:ByteArray
    // Whether asc is written to reader.
    public var ascWritten:Boolean
    
    public function Decoder()
    {
        samples = new Mp4SampleManager()
    }
    
    public function parse_piece_range(piece_id:uint):Object {
        var obj:Object = {};
        // check if piece time exceed duration
        var st_ms:uint = piece_id * Mp4RangeFlv.PerPieceSeconds * 1000;
        var end_ms:uint = (piece_id + 1) * Mp4RangeFlv.PerPieceSeconds * 1000;
        if (st_ms >= this.duration) {
            return obj;
        }
        if (end_ms >= this.duration) {
            end_ms = this.duration;
        }
        return this.samples.parse_sample_range(st_ms, end_ms);
    }
    
    public function parse_moov(moov:MoovBox):void {
        var mvhd:MvhdBox = moov.Mvhd
        if (!mvhd) {
            trace("can't find mvhd box in moov")
            return
        }
        this.duration = Number(mvhd.duration())
        
        var vide:TracBox = moov.Video 
        if (!vide) {
            trace("can't find video trac in moov")
            return
        }
        
        var soun:TracBox = moov.Audio
        if (!soun) {
            trace("can't find soun trac in moov")
            return
        }
        
        var avc1:Avc1Box = vide.avc1
        if (!avc1) {
            trace("can't find avc1 in vide trac")
            return
        }
        this.width = avc1.width
        this.height = avc1.height
        
        var mp4a:Mp4aBox = soun.mp4a 
        
        var sr:uint = mp4a.sample_rate
        if (sr >= 44100) {
            this.sample_rate = BaseMP4.SrsAudioSampleRate44100
        } else if (sr >= 22050) {
            this.sample_rate = BaseMP4.SrsAudioSampleRate22050
        } else if (sr >= 11025) {
            this.sample_rate = BaseMP4.SrsAudioSampleRate11025
        } else {
            this.sample_rate = BaseMP4.SrsAudioSampleRate5512
        }
        
        if (mp4a.sample_size == 16) {
            this.sample_size = BaseMP4.SrsAudioSampleBits16bit
        } else {
            this.sample_size = BaseMP4.SrsAudioSampleBits8bit
        }
        
        if (mp4a.channel_count == 2) {
            this.channels = BaseMP4.SrsAudioChannelsStereo
        } else {
            this.channels = BaseMP4.SrsAudioChannelsMono
        }
        
        var avcc:AvccBox = vide.avcc
        if (!avcc) {
            trace("avcc not find in vide")
            return
        }
        var asc:Mp4DecoderSpecificInfo = soun.asc 
        if (!asc) {
            trace("asc not find in vide")
            return
        }   
        
        this.vcodec = vide.vide_codec
        this.acodec = soun.soun_codec
        
        this.pavcc = avcc.avc_config
        this.pasc = asc.asc  
        trace(this.pavcc.bytesAvailable, this.pasc.bytesAvailable) 
        
        this.samples.load(moov)
        
        trace("dur=", duration, "vide=", vcodec, moov.NbVideoTracks, "soun=", acodec, moov.NbAudioTracks, sample_rate, sample_size, channels, width, height)
    }
    
    public function read_video_sh_sample():SrsMp4Sample {
        var s:SrsMp4Sample = new SrsMp4Sample()
        if (!this.avccWritten && this.pavcc.length != 0) {
            this.avccWritten = true
            s.handler_type = BaseMP4.SrsMp4HandlerTypeVIDE
            s.nb_sample = this.pavcc.length
            this.pavcc.position = 0
            s.sample.writeBytes(this.pavcc) 
            s.sample.position = 0
            s.frame_ype = BaseMP4.SrsVideoAvcFrameTypeKeyFrame
            s.frame_trait = BaseMP4.SrsVideoAvcFrameTraitSequenceHeader
                
            s.codec = this.vcodec
            trace("make a video sh") 
            return s
        }
        return null
    }
    
    public function read_audio_sh_sample():SrsMp4Sample {
        var s:SrsMp4Sample = new SrsMp4Sample()
        if (!this.ascWritten && this.pasc.length != 0) {
            this.ascWritten = true
            s.handler_type = BaseMP4.SrsMp4HandlerTypeSOUN
            s.nb_sample = this.pasc.length
            this.pasc.position = 0
            s.sample.writeBytes(this.pasc)
            s.sample.position = 0
            s.frame_ype = 0
            s.frame_trait = BaseMP4.SrsAudioAacFrameTraitSequenceHeader  
                
            s.codec = this.acodec
            s.sample_rate = this.sample_rate
            s.channels = this.channels
            s.sound_bits = this.sample_size
            trace("make a audio sh") 
            return s
        }
        return null
    }
    
    public function read_sample(index:uint, source:ByteArray, relative_offset:uint):SrsMp4Sample {
        var s:SrsMp4Sample = new SrsMp4Sample()
        if (index >= this.samples.samples.length) {
            trace("sample reach end")
            return null
        }
        
        var ms:Mp4Sample = this.samples.samples[index]
        if (ms.sample_type == BaseMP4.SrsFrameTypeVideo) {
            s.handler_type = BaseMP4.SrsMp4HandlerTypeVIDE
            s.frame_trait = BaseMP4.SrsVideoAvcFrameTraitNALU
            s.codec = this.vcodec
        } else {
            s.handler_type = BaseMP4.SrsMp4HandlerTypeSOUN
            s.frame_trait = BaseMP4.SrsAudioAacFrameTraitRawData 
            
            s.codec = this.acodec
            s.sample_rate = this.sample_rate
            s.channels = this.channels
            s.sound_bits = this.sample_size    
        }
        s.dts = ms.dts_ms
        s.pts = ms.pts_ms
        s.frame_ype = ms.frame_type
        s.nb_sample = ms.nb_data
            
        //trace("read sample, ms offset=", ms.offset, "len=", ms.nb_data, "relative=", relative_offset, "source available=", source.bytesAvailable);
        s.sample.writeBytes(source, ms.offset - relative_offset, ms.nb_data)
        s.sample.position = 0    
        return s
    }
    
    /*private function read_sample(mp4_file:ByteArray):SrsMp4Sample {
        var s:SrsMp4Sample = new SrsMp4Sample()        
        this.curIndex ++
        if(this.curIndex >= this.samples.samples.length) {
            trace("sample reach end")
            return null
        }
        
        var ms:Mp4Sample = this.samples.samples[this.curIndex]
        if (ms.sample_type == BaseMP4.SrsFrameTypeVideo) {
            s.handler_type = BaseMP4.SrsMp4HandlerTypeVIDE
            s.frame_trait = BaseMP4.SrsVideoAvcFrameTraitNALU
            s.codec = this.vcodec
        } else {
            s.handler_type = BaseMP4.SrsMp4HandlerTypeSOUN
            s.frame_trait = BaseMP4.SrsAudioAacFrameTraitRawData 
                
            s.codec = this.acodec
            s.sample_rate = this.sample_rate
            s.channels = this.channels
            s.sound_bits = this.sample_size    
        }
        s.dts = ms.dts_ms
        s.pts = ms.pts_ms
        s.frame_ype = ms.frame_type
        s.nb_sample = ms.nb_data
        s.sample.writeBytes(mp4_file, ms.offset, ms.nb_data)
        s.sample.position = 0    
        return s
    }*/
}

class Mp4SampleManager {
    public var samples:Vector.<Mp4Sample>
    
    public function Mp4SampleManager() {
        samples = new Vector.<Mp4Sample>()
    }
    
    private function load_trak(frame_type:uint, track:TracBox):Vector.<Mp4Sample> {
        var mdhd:MdhdBox = track.mdhd
        var stco:StcoBox = track.stco
        var stsz:StszBox = track.stsz    
        var stsc:StscBox = track.stsc
        var stts:SttsBox = track.stts
        var ctts:CttsBox
        var stss:StssBox  
        
        var tses:Vector.<Mp4Sample> = new Vector.<Mp4Sample>()
        
        if (!mdhd || !stco || !stsz || !stsc || !stts) {
            return null
        }
        
        if (frame_type == BaseMP4.SrsFrameTypeVideo) {
            ctts = track.ctts
            stss = track.stss    
        }
        
        // Samples per chunk.
        stsc.initialize_counter()
        // DTS box
        stts.initialize_counter() 
        if (stts.entries.length == 0) {
            return null
        }
        // CTS PTS box
        if (ctts) {
            ctts.initialize_counter()
            if (ctts.entries.length == 0) {
                return null
            }
        }
        
        var previous:Mp4Sample
        
        for (var ci:uint = 0; ci < stco.entry_count; ci ++) {
            // The sample offset relative in chunk.
            var sample_relative_offset:uint = 0
            
            // Find how many samples from stsc.
            var entry:Mp4StscEntry = stsc.on_chunk(ci)   
            for (var i:uint = 0; i < entry.samples_per_chunk; i++) {
                var sample:Mp4Sample = new Mp4Sample()
                sample.sample_type = frame_type
                if (previous) {
                    sample.index = previous.index + 1
                }
                sample.tbn = mdhd.TimeScale
                sample.offset = stco.entries[ci] + sample_relative_offset   
                
                var sample_size:uint = stsz.sample_size(sample.index)
                if (sample_size == 0) {
                    return null
                }
                sample_relative_offset += sample_size
                
                var sttsEntry:Mp4SttsEntry = stts.on_sample(sample.index)
                if (!sttsEntry) {
                    return null
                }
                
                if (previous) {
                    sample.dts = previous.dts + sttsEntry.sampleDelta
                    sample.pts = sample.dts
                }
                
                if (ctts) {
                    var cttsEntry:Mp4CttsEntry = ctts.on_sample(sample.index)
                    if (!cttsEntry) {
                        return null
                    }
                    sample.pts = sample.dts + cttsEntry.sampleOffset
                }
                
                if (frame_type == BaseMP4.SrsFrameTypeVideo) {
                    if (!stss || stss.is_sync(sample.index)) {
                        sample.frame_type = BaseMP4.SrsVideoAvcFrameTypeKeyFrame
                    } else {
                        sample.frame_type = BaseMP4.SrsVideoAvcFrameTypeInterFrame
                    }
                }
                
                sample.nb_data = sample_size
                previous = sample
                tses.push(sample)
            }
        }
        
        trace("load total samples:", tses.length)
        if (previous && previous.index + 1 != stsz.sample_count) {
            trace("MP4 illegal samples count, exp=", stsz.sample_count, "actual=", previous.index + 1)
            return null
        }
        return tses
    }
    
    private function do_load(moov:MoovBox):Vector.<Mp4Sample> {
        var vide:TracBox = moov.Video
        if (!vide) {
            return null
        }
        var vstss:Vector.<Mp4Sample> = load_trak(BaseMP4.SrsFrameTypeVideo, vide)
        if (!vstss) {
            return null
        }
        trace("load video trak ok, stss len=", vstss.length)
        
        var soun:TracBox = moov.Audio
        if (!soun) {
            return null
        }
        var astss:Vector.<Mp4Sample> = load_trak(BaseMP4.SrsFrameTypeAudio, soun)
        if (!astss) {
            return null
        }
        trace("load audio trak ok, stss len=", astss.length)
        
        var stss:Vector.<Mp4Sample> = new Vector.<Mp4Sample>()
        vstss.forEach(function(item:Mp4Sample, index:int, vector:Vector.<Mp4Sample>):void {
            stss.push(item)
        }) 
        
        astss.forEach(function(item:Mp4Sample, index:int, vector:Vector.<Mp4Sample>):void {
            stss.push(item)
        })  
        
        return stss
    }
    
    public function load(moov:MoovBox):void {
        var tses:Vector.<Mp4Sample> = do_load(moov)
        if (!tses) {
            return
        }
        
        // sort 
        var sortFunc:Function = function (x:Mp4Sample, y:Mp4Sample):int {
            if (x.offset < y.offset) {
                return -1
            } 
            if (x.offset > y.offset) {
                return 1
            }
            return 0
        }
        tses.sort(sortFunc);
        trace("after sort, tses len=", tses.length, "first=", tses[0].frame_type, tses[0].dts, tses[0].pts, tses[0].offset, tses[0].nb_data)
        
        // Dumps temp samples.
        // Adjust the sequence diff.
        var maxp:int
        var maxn:int
        
        var pvideo:Mp4Sample
        for (var i:int = 0; i < tses.length; i++) {
            var ts:Mp4Sample = tses[i] 
            //trace("sample, k:", i, ts.frame_type, ts.dts, ts.pts, ts.offset, ts.nb_data)
            if (ts.sample_type == BaseMP4.SrsFrameTypeVideo) {
                pvideo = ts
            } else if (pvideo) {
                // deal video and audio sample diff
                var diff:int = int(ts.dts_ms) - int(pvideo.dts_ms)
                if (diff > 0) {
                    maxp = Math.max(diff, maxp)    
                } else {
                    maxn = Math.min(diff, maxn)
                }
                pvideo = null
            }
        }
        
        trace("maxp=", maxp, "maxn=", maxn)
        // Adjust when one of maxp and maxn is zero,
        // that means we can adjust by add maxn or sub maxp,
        // notice that maxn is negative and maxp is positive.
        if (maxp * maxn == 0 && maxp + maxn != 0) {
            for (var j:int = 0; j < tses.length; j ++) {
                var tmp:Mp4Sample = tses[j]
                if (tmp.sample_type == BaseMP4.SrsFrameTypeAudio) {
                    tmp.adjust = 0 - maxp - maxn
                }
            }
        }
        
        tses.forEach(function(item:Mp4Sample, index:int, vector:Vector.<Mp4Sample>):void {
            //trace("after adjust sample, k:", i, ts.frame_type, ts.dts, ts.pts, ts.offset, ts.nb_data)
            samples.push(item)
        })
        return    
    }

    public function parse_sample_range(st_ms:uint, end_ms:uint):Object {
        var off:Object = {
            st_sid: -1,
            end_sid: -1
        };
           
        trace(".............parse sample range, st_ms=", st_ms, "end_ms=", end_ms, "max=", samples[samples.length - 1].dts_ms);
        for (var i:uint = 0; i < samples.length; i++) {
            var s:Mp4Sample = samples[i];
            if (off.st_sid == -1 && s.dts_ms >= st_ms) {
                off.st_sid = i;
            }
            if (off.end_sid == -1 && s.dts_ms >= end_ms) {
                off.end_sid = i;
            }
        }
        
        if (off.end_sid <= off.st_sid) {
            return {};
        }
        trace(".............st_sid=", off.st_sid, "end_sid=", off.end_sid);
        return off    
    }
    
    public function get_offset(sample_id:uint):uint {
        if (sample_id >= samples.length) {
            return samples.length - 1;
        }
        return samples[sample_id].offset
    }
}

class Mp4Sample {
    // The type of sample, audio or video.
    public var sample_type:uint
    // The offset of sample in file.
    public var offset:uint
    // The index of sample with a track, start from 0.
    public var index:uint
    // The dts in tbn.
    public var dts:uint
    // For video, the pts in tbn.
    public var pts:uint
    // The tbn(timebase).
    public var tbn:uint
    // For video, the frame type, whether keyframe.
    public var frame_type:uint
    
    // The adjust timestamp in milliseconds.
    // For example, we can adjust a timestamp for A/V to monotonically increase.
    public var adjust:int
    
    // The sample data.
    public var nb_data:uint
    public var data:Array
    
    public function Mp4Sample() {
        data = new Array()
    }
    
    public function get dts_ms():uint {
        if (tbn > 0) {
            return uint(int(dts * 1000 / tbn) + adjust)
        }
        return 0
    }
    
    public function get pts_ms():uint {
        if (tbn > 0) {
            return uint(int(pts * 1000 / tbn) + adjust)
        }
        return 0
    }
}
import flash.utils.ByteArray;

class Box
{
    public var size:uint = 0;
    public var position:uint = 0;
    public var offset:uint = 0;
    public var type:uint = 0;
    private var _data:ByteArray;
    
    public var Boxes:Array;
    
    public function Box(type:uint)
    {
        this.Boxes = new Array();
    }
    
    public function discovery(byte:ByteArray):Box
    {
        this._data = byte;
        
        var pos:uint = byte.position
        var tmp_size:uint = _data.readUnsignedInt();
        var tmp_type:uint = _data.readUnsignedInt();
        if (tmp_size == 1)
        {
            tmp_size = _data.readDouble();
        }
        var off:uint = byte.position - pos;
        
        var box:Box = null;
        
        trace("discovery:", tmp_size, tmp_type.toString(16))
        box = BaseMP4.getBox(tmp_type);
        if (box) {
            box.size = tmp_size;
            box.position = pos;
            box.offset = off;
            box.type = tmp_type;
            trace("size:", box.size, "position:", box.position, "offset:", box.offset, "type:0x", box.type.toString());
        }
        return box;
    }
    
    public function decode_header(byte:ByteArray):void
    {
        //
    }
    
    public function decode_boxes(byte:ByteArray):void
    {
        while (byte.bytesAvailable > 0) {
            var box:Box = discovery(byte);
            if (box) {
                var d:ByteArray = new ByteArray();
                d.writeBytes(byte, box.position + box.offset, box.size - box.offset);
                d.position = 0;
                box.decode_header(d);
                box.decode_boxes(d);
                byte.position = box.position + box.size;
                
                Boxes.push(box);
            } else{
                break;
            }
        }
    }
    
    // Get the contained box of specific type.
    // @return The first matched box.
    public function getBox(bt:uint):Box {
        for (var i:int = 0; i < this.Boxes.length; i++) {
            var box:Box = this.Boxes[i]
            if (box.type == bt) {
                return box
            }
        }
        return null
    }
}

/*********************************************************************/
class MoovBox extends Box
{
    public function MoovBox()
    {
        super(BaseMP4.SrsMp4BoxTypeMOOV);
        trace("[moov]");
    }
    
    public function get Mvhd():MvhdBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeMVHD)
        if (box) {
            return MvhdBox(box)
        }
        return null
    }
    
    public function get Video():TracBox {
        for (var i:int = 0; i < this.Boxes.length; i++) {
            var box:Box = this.Boxes[i]
            if (box.type == BaseMP4.SrsMp4BoxTypeTRAK) {
                var tbox:TracBox = TracBox(box)
                if (tbox.trakType() == BaseMP4.SrsMp4TrackTypeVideo) {
                    return tbox
                }    
            }
        }
        return null
    }
    
    public function get NbVideoTracks():uint {
        var nb_tracks:uint = 0
        for (var i:int = 0; i < this.Boxes.length; i++) {
            var box:Box = this.Boxes[i]
            if (box.type == BaseMP4.SrsMp4BoxTypeTRAK) {
                var tbox:TracBox = TracBox(box)
                if (tbox.trakType() == BaseMP4.SrsMp4TrackTypeVideo) {
                    nb_tracks++
                }
            }
        }
        return nb_tracks  
    }
    
    public function get Audio():TracBox {
        for (var i:int = 0; i < this.Boxes.length; i++) {
            var box:Box = this.Boxes[i]
            if (box.type == BaseMP4.SrsMp4BoxTypeTRAK) {
                var tbox:TracBox = TracBox(box)
                if (tbox.trakType() == BaseMP4.SrsMp4TrackTypeAudio) {
                    return tbox
                }    
            }
        }
        return null
    }
    
    public function get NbAudioTracks():uint {
        var nb_tracks:uint = 0
        for (var i:int = 0; i < this.Boxes.length; i++) {
            var box:Box = this.Boxes[i]
            if (box.type == BaseMP4.SrsMp4BoxTypeTRAK) {
                var tbox:TracBox = TracBox(box)
                if (tbox.trakType() == BaseMP4.SrsMp4TrackTypeAudio) {
                    nb_tracks++
                }
            }
        }
        return nb_tracks  
    }
}

/*********************************************************************/
class MvhdBox extends Box
{
    private var _version:uint;
    private var _flags:uint;
    
    private var create_time:uint;
    private var mod_time:uint;
    private var time_scale:uint;
    private var duration_in_tbn:uint;
    
    public function MvhdBox()
    {
        super(BaseMP4.SrsMp4BoxTypeMVHD)
        trace("[mvhd]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        _flags = byte.readUnsignedInt();
        _version = (_flags >> 24)& 0xff;
        _flags = _flags & 0x00ffffff
        
        if (_version == 1) {
            // read 64 bit data
        } else {
            this.create_time = byte.readUnsignedInt();
            this.mod_time = byte.readUnsignedInt();
            this.time_scale = byte.readUnsignedInt();
            this.duration_in_tbn = byte.readUnsignedInt();
            trace("[mvhd] duration=", this.duration());
        }
        
        byte.position = byte.position + byte.bytesAvailable
    }
    
    public function duration():uint
    {
        if (this.time_scale > 0) {
            return this.duration_in_tbn * 1000 / this.time_scale;
        }
        return 0;
    }
}

/*********************************************************************/
class TracBox extends Box
{
    public function TracBox()
    {
        super(BaseMP4.SrsMp4BoxTypeTRAK);
        trace("[trac box]");
    }
    
    public function trakType():uint {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeMDIA)
        if (box) {
            var nbox:MdiaBox = MdiaBox(box)
            return nbox.trakType()    
        }
        return BaseMP4.SrsMp4TrackTypeForbidden
    }
    
    public function get mdhd():MdhdBox {
        var box:MdiaBox = this.mdia
        if (box) {
            return box.mdhd
        }
        return null
    }
    
    public function get mdia():MdiaBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeMDIA)
        if (box) {
            return MdiaBox(box)
        }
        return null
    }
    
    public function get minf():MinfBox {
        var box:MdiaBox = this.mdia
        if (box) {
            return box.minf
        }
        return null
    }
    
    public function get stbl():StblBox {
        var box:MinfBox = this.minf
        if (box) {
            return box.stbl
        }
        return null
    }
    
    public function get stss():StssBox {
        var box:StblBox = this.stbl
        if (box) {
            return box.stss
        }
        return null
    }
    
    public function get ctts():CttsBox {
        var box:StblBox = this.stbl
        if (box) {
            return box.ctts
        }
        return null
    }
    
    public function get stts():SttsBox {
        var box:StblBox = this.stbl
        if (box) {
            return box.stts
        }
        return null
    }
    
    public function get stsc():StscBox {
        var box:StblBox = this.stbl
        if (box) {
            return box.stsc
        }
        return null
    }
    
    public function get stsz():StszBox {
        var box:StblBox = this.stbl
        if (box) {
            return box.stsz
        }
        return null
    }
    
    public function get stco():StcoBox {
        var box:StblBox = this.stbl
        if (box) {
            return box.stco
        }
        return null
    }
    
    public function get stsd():StsdBox {
        var box:StblBox = this.stbl
        if (box) {
            return box.stsd
        }
        return null
    }
    
    public function get avc1():Avc1Box {
        var box:StsdBox = this.stsd
        if (box) {
            return box.avc1
        }
        return null
    }
    
    public function get mp4a():Mp4aBox {
        var box:StsdBox = this.stsd
        if (box) {
            return box.mp4a
        }
        return null    
    }
    
    public function get avcc():AvccBox {
        var box:Avc1Box = this.avc1
        if (box) {
            return box.avcc
        }
        return null
    }
    
    public function get asc():Mp4DecoderSpecificInfo {
        var box:Mp4aBox = this.mp4a
        if (box) {
            return box.asc
        }
        return null    
    }
    
    public function get vide_codec():uint {
        var box:StsdBox = this.stsd
        if (box && box.entries.length > 0) {
            var entry:Box = box.entries[0]
            if (entry.type == BaseMP4.SrsMp4BoxTypeAVC1) {
                return BaseMP4.SrsVideoCodecIdAVC
            }
        }
        return BaseMP4.SrsVideoCodecIdForbidden
    }
    
    public function get soun_codec():uint {
        var box:StsdBox = this.stsd
        if (box && box.entries.length > 0) {
            var entry:Box = box.entries[0]
            if (entry.type == BaseMP4.SrsMp4BoxTypeMP4A) {
                return BaseMP4.SrsAudioCodecIdAAC
            }
        }
        return BaseMP4.SrsAudioCodecIdForbidden
    }
}

class TkhdBox extends Box
{
    public function TkhdBox()
    {
        super(BaseMP4.SrsMp4BoxTypeTKHD);
        trace("[tkhd]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        byte.position = byte.position + byte.bytesAvailable
    }
}

class MdiaBox extends Box
{
    public function MdiaBox()
    {
        super(BaseMP4.SrsMp4BoxTypeMDIA);
        trace("[mdia]");
    }
    
    public function trakType():uint {
        var nbox:HdlrBox
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeHDLR)
        if (box) {
            nbox = HdlrBox(box)
            if (nbox.hdlr_type == BaseMP4.SrsMp4HandlerTypeVIDE) {
                return BaseMP4.SrsMp4TrackTypeVideo
            }
            if (nbox.hdlr_type == BaseMP4.SrsMp4HandlerTypeSOUN) {
                return BaseMP4.SrsMp4TrackTypeAudio
            }
        }
        return BaseMP4.SrsMp4TrackTypeForbidden
    }
    
    public function get mdhd():MdhdBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeMDHD)
        if (box) {
            return MdhdBox(box)   
        }
        trace("can't find mdhd in mdia")
        return null
    }
    
    public function get minf():MinfBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeMINF)
        if (box) {
            return MinfBox(box)   
        }
        
        trace("can't find minf in mdia")
        return null
    }
}

/**
 * 8.4.2 Media Header Box (mdhd)
 * ISO_IEC_14496-12-base-format-2012.pdf, page 36
 * The media declaration container contains all the objects that declare information about the media data within a
 * track.
 */
class MdhdBox extends Box
{
    private var _flags:uint
    private var _version:uint
    
    // an integer that declares the creation time of the presentation (in seconds since
    // midnight, Jan. 1, 1904, in UTC time)
    public var CreateTime:Number
    // an integer that declares the most recent time the presentation was modified (in
    // seconds since midnight, Jan. 1, 1904, in UTC time)
    public var ModTime:Number
    // an integer that specifies the time-scale for the entire presentation; this is the number of
    // time units that pass in one second. For example, a time coordinate system that measures time in
    // sixtieths of a second has a time scale of 60.
    public var TimeScale:uint
    // an integer that declares length of the presentation (in the indicated timescale). This property
    // is derived from the presentation’s tracks: the value of this field corresponds to the duration of the
    // longest track in the presentation. If the duration cannot be determined then duration is set to all 1s.
    public var Duration:uint
    
    public function MdhdBox()
    {
        super(BaseMP4.SrsMp4BoxTypeMDHD)
        trace("[mdhd]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // mp4 full box
        // read tag, version
        _flags = byte.readUnsignedInt();
        _version = (_flags >> 24)& 0xff;
        _flags = _flags & 0x00ffffff
        
        if (this._version == 1) {
            byte.position += 8 *2    
        } else {
            byte.position += 4 * 2
        }
        
        this.TimeScale = byte.readUnsignedInt()    
        byte.position = byte.position + byte.bytesAvailable
    }
}

class HdlrBox extends Box
{
    public static const SrsMp4HandlerTypeVIDE:uint = 0x76696465 // 'vide'
    public static const SrsMp4HandlerTypeSOUN:uint = 0x736f756e // 'soun'
    // an integer containing one of the following values, or a value from a derived specification:
    //      ‘vide’, Video track
    //      ‘soun’, Audio track
    public var hdlr_type:uint
    
    public function HdlrBox()
    {
        super(BaseMP4.SrsMp4BoxTypeHDLR)
        trace("[hdlr]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        byte.position += 8;
        this.hdlr_type = byte.readUnsignedInt();
        byte.position = byte.position + byte.bytesAvailable;
        byte.position = byte.position + byte.bytesAvailable
    }
}

class MinfBox extends Box
{
    public function MinfBox()
    {
        super(BaseMP4.SrsMp4BoxTypeMINF)
        trace("[minf]");
    }
    
    /*override public function decode_header(byte:ByteArray):void
    {
    byte.position = byte.position + byte.bytesAvailable
    }*/
    
    public function get stbl():StblBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeSTBL)
        if (box) {
            return StblBox(box)
        }
        return null
        
    }
}

class StblBox extends Box
{
    public function StblBox()
    {
        super(BaseMP4.SrsMp4BoxTypeSTBL)
        trace("[stbl]");
    }
    
    public function get stss():StssBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeSTSS)
        if (box) {
            return StssBox(box)
        }
        trace("can't find stss in stbl")
        return null
    }
    
    public function get ctts():CttsBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeCTTS)
        if (box) {
            return CttsBox(box)
        }
        trace("can't find ctts in stbl")
        return null
    }
    
    public function get stts():SttsBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeSTTS)
        if (box) {
            return SttsBox(box)
        }
        trace("can't find stts in stbl")
        return null
    }
    
    public function get stsc():StscBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeSTSC)
        if (box) {
            return StscBox(box)
        }
        trace("can't find stsc in stbl")
        return null
    }
    
    public function get stsz():StszBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeSTSZ)
        if (box) {
            return StszBox(box)
        }
        trace("can't find stsz in stbl")
        return null
    }
    
    public function get stco():StcoBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeSTCO)
        if (box) {
            return StcoBox(box)
        }
        trace("can't find stco in stbl")
        return null
    }
    
    public function get stsd():StsdBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeSTSD)
        if (box) {
            return StsdBox(box)
        }
        trace("can't find stsd in stbl")
        return null
    }
}

/**
 * 8.7.5 Chunk Offset Box (stco), for Audio/Video.
 * ISO_IEC_14496-12-base-format-2012.pdf, page 59
 * The chunk offset table gives the index of each chunk into the containing file. There are two variants, permitting
 * the use of 32-bit or 64-bit offsets. The latter is useful when managing very large presentations. At most one of
 * these variants will occur in any single instance of a sample table.
 */
class StcoBox extends Box
{
    // an integer that gives the number of entries in the following table
    private var _entry_count:uint
    // a 32 bit integer that gives the offset of the start of a chunk into its containing
    // media file.
    private var _entries:Array
    
    public function StcoBox()
    {
        super(BaseMP4.SrsMp4BoxTypeSTCO)
        _entries = new Array()
        trace("[stco]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip version, flag   4 bytes
        byte.position += 4
        this._entry_count = byte.readUnsignedInt()
        for (var i:int = 0; i < this._entry_count; i++) {
            this._entries.push(byte.readUnsignedInt())
        }
        trace("stco entries, len=", entries.length, this._entry_count)    
        byte.position = byte.position + byte.bytesAvailable   
    }
    
    public function get entries():Array {
        return this._entries
    }
    
    public function get entry_count():uint {
        return this._entry_count
    }
}

/**
 * 8.7.3.2 Sample Size Box (stsz), for Audio/Video.
 * ISO_IEC_14496-12-base-format-2012.pdf, page 58
 * This box contains the sample count and a table giving the size in bytes of each sample. This allows the media data
 * itself to be unframed. The total number of samples in the media is always indicated in the sample count.
 */
class StszBox extends Box
{
    private var _sample_size:uint
    private var _sample_count:uint
    private var _entry_sizes:Array
    
    public function StszBox()
    {
        super(BaseMP4.SrsMp4BoxTypeSTSZ)
        _entry_sizes = new Array()
        trace("[stsz]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip version, flag   4 bytes
        byte.position += 4
        
        this._sample_size = byte.readUnsignedInt()
        this._sample_count = byte.readUnsignedInt()
        if (this._sample_size == 0) {
            for (var i:int = 0; i < this._sample_count; i++) {
                var size:uint = byte.readUnsignedInt()
                this._entry_sizes.push(size)    
            }
        }
        
        trace("debug, decode stsz, sample_size=", this._sample_size, "sample_count=", this._sample_count)
        byte.position = byte.position + byte.bytesAvailable   
    }
    
    public function sample_size(index:int):uint {
        if (this._sample_size != 0) {
            return this._sample_size
        }
        
        if (index >= this._sample_count) {
            trace("error, MP4 stsz overflow, sample_count=", this._sample_count, "req index=", index)
            return 0
        }
        return this._entry_sizes[index]
    }
    
    public function get sample_count():uint {
        return this._sample_count
    }
}

/*************************************************************************************************************/
/**
 * 8.7.4 Sample To Chunk Box (stsc), for Audio/Video.
 * ISO_IEC_14496-12-base-format-2012.pdf, page 58
 * Samples within the media data are grouped into chunks. Chunks can be of different sizes, and the samples
 * within a chunk can have different sizes. This table can be used to find the chunk that contains a sample,
 * its position, and the associated sample description.
 */
class StscBox extends Box
{
    private var _entry_count:uint
    private var _entries:Array
    private var _index:uint
    
    public function StscBox()
    {
        super(BaseMP4.SrsMp4BoxTypeSTSC)
        this._entries = new Array()
        trace("[stsc]")
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip version, flag   4 bytes
        byte.position += 4
        
        this._entry_count = byte.readUnsignedInt()  
        for (var i:int = 0; i < this._entry_count; i ++) {
            var entry:Mp4StscEntry = new Mp4StscEntry()
            entry.first_chunk = byte.readUnsignedInt()
            entry.samples_per_chunk = byte.readUnsignedInt()
            entry.sample_description_index = byte.readUnsignedInt()
            this._entries.push(entry)    
        }
        byte.position = byte.position + byte.bytesAvailable
    }
    
    public function initialize_counter():void {
        this._index = 0
    }
    
    public function on_chunk(chunk_index:int):Mp4StscEntry {
        // Last chunk?
        if (this._index >= this._entry_count - 1) {
            trace("last chunk, stsc.index=", this._index)
            return this._entries[this._index]
        }
        
        // move to next chunk?
        if (chunk_index + 1 >= Mp4StscEntry(this._entries[this._index + 1]).first_chunk) {
            trace("moce to next chunk")
            this._index ++
        }
        return this._entries[this._index]
    }
}

class Mp4StscEntry {
    // an integer that gives the index of the first chunk in this run of chunks that share the
    // same samples-per-chunk and sample-description-index; the index of the first chunk in a track has the
    // value 1 (the first_chunk field in the first record of this box has the value 1, identifying that the first
    // sample maps to the first chunk).
    public var first_chunk:uint
    // an integer that gives the number of samples in each of these chunks
    public var samples_per_chunk:uint
    // an integer that gives the index of the sample entry that describes the
    // samples in this chunk. The index ranges from 1 to the number of sample entries in the Sample
    // Description Box
    public var sample_description_index:uint
    
    public function Mp4StscEntry()
    {
    }
}
/*************************************************************************************************************/
/**
 * 8.6.1.2 Decoding Time to Sample Box (stts), for Audio/Video.
 * ISO_IEC_14496-12-base-format-2012.pdf, page 48
 * This box contains a compact version of a table that allows indexing from decoding time to sample number.
 * Other tables give sample sizes and pointers, from the sample number. Each entry in the table gives the
 * number of consecutive samples with the same time delta, and the delta of those samples. By adding the
 * deltas a complete time-to-sample map may be built.
 */
class SttsBox extends Box
{
    // an integer that gives the number of entries in the following table.
    private var _entry_count:uint
    private var _entries:Array
    
    private var _index:uint
    private var _count:uint
    
    public function SttsBox()
    {
        super(BaseMP4.SrsMp4BoxTypeSTTS)
        this._entries = new Array()
        trace("[stts]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip version, flag   4 bytes
        byte.position += 4
        
        this._entry_count = byte.readUnsignedInt()
        for (var i:int = 0; i < this._entry_count; i ++) {
            var entry:Mp4SttsEntry = new Mp4SttsEntry()
            entry.sampleCount = byte.readUnsignedInt()
            entry.sampleDelta = byte.readUnsignedInt()
            this._entries.push(entry)    
        }
        byte.position = byte.position + byte.bytesAvailable
    }
    
    public function initialize_counter():void {
        this._index = 0
        if (this._entries.length == 0) {
            trace("MP4 illegal ts, empty stts")
            return
        }
        this._count = Mp4SttsEntry(this._entries[0]).sampleCount
    }
    
    public function on_sample(sample_index:uint):Mp4SttsEntry {
        if (sample_index+ 1 > this._count) {
            this._index ++
            if (this._index >= this._entry_count) {
                trace("error, MP4 illegal ts, stts overflow, count=", this._entry_count, "index=", this._index)
                return null
            }
            this._count += Mp4SttsEntry(this._entries[this._index]).sampleCount
        }
        return this._entries[this._index]
    }
    
    public function get entries():Array {
        return this._entries
    }
}

class Mp4SttsEntry
{
    // an integer that counts the number of consecutive samples that have the given
    // duration.
    public var sampleCount:uint
    // an integer that gives the delta of these samples in the time-scale of the media.
    public var sampleDelta:uint
    public function Mp4SttsEntry()
    {
    }   
}
/*************************************************************************************************************/
/**
 * 8.6.1.3 Composition Time to Sample Box (ctts), for Video.
 * ISO_IEC_14496-12-base-format-2012.pdf, page 49
 * This box provides the offset between decoding time and composition time. In version 0 of this box the
 * decoding time must be less than the composition time, and the offsets are expressed as unsigned numbers
 * such that CT(n) = DT(n) + CTTS(n) where CTTS(n) is the (uncompressed) table entry for sample n. In version
 * 1 of this box, the composition timeline and the decoding timeline are still derived from each other, but the
 * offsets are signed. It is recommended that for the computed composition timestamps, there is exactly one with
 * the value 0 (zero).
 */
class CttsBox extends Box
{
    private var _version:uint;
    private var _flags:uint;
    
    // an integer that gives the number of entries in the following table.
    private var _entry_count:uint
    private var _entries:Array
    
    private var _index:uint
    private var _count:uint
    
    public function CttsBox()
    {
        super(BaseMP4.SrsMp4BoxTypeCTTS)
        this._entries = new Array()
        trace("[ctts]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // mp4 full box
        // read tag, version
        _flags = byte.readUnsignedInt();
        _version = (_flags >> 24)& 0xff;
        _flags = _flags & 0x00ffffff
        
        this._entry_count = byte.readUnsignedInt()
        for (var i:int = 0; i < this._entry_count; i++) {
            var entry:Mp4CttsEntry = new Mp4CttsEntry()
            entry.sampleCount = byte.readUnsignedInt()
            if (this._version == 0) {
                entry.sampleOffset = int(byte.readUnsignedInt())
            } else {
                entry.sampleOffset = byte.readInt()
            }
            trace("decode one ctts entry, entry count=", entry.sampleCount, "offset=", entry.sampleOffset)
            this._entries.push(entry)
        }
        byte.position = byte.position + byte.bytesAvailable    
    }
    
    public function initialize_counter():void {
        this._index = 0
        if (this._entries.length == 0) {
            trace("MP4 illegal ts, empty cttx")
            return
        }
        this._count = Mp4CttsEntry(this._entries[0]).sampleCount
    }
    
    public function on_sample(sample_index:uint):Mp4CttsEntry {
        if (sample_index+ 1 > this._count) {
            this._index ++
            if (this._index >= this._entry_count) {
                trace("error, MP4 illegal ts, ctts overflow, count=", this._entry_count, "index=", this._index)
                return null
            }
            this._count += Mp4CttsEntry(this._entries[this._index]).sampleCount
        }
        return this._entries[this._index]
    }
    
    public function get entries():Array {
        return this._entries
    }
}

class Mp4CttsEntry
{
    // an integer that counts the number of consecutive samples that have the given offset.
    public var sampleCount:uint
    // uint32_t for version=0
    // int32_t for version=1
    // an integer that gives the offset between CT and DT, such that CT(n) = DT(n) +
    // CTTS(n).
    public var sampleOffset:int
    public function Mp4CttsEntry()
    {
    }
}
/*************************************************************************************************************/
class StssBox extends Box
{
    // an integer that gives the number of entries in the following table. If entry_count is zero,
    // there are no sync samples within the stream and the following table is empty.
    private var _entry_count:uint
    // the numbers of the samples that are sync samples in the stream.
    private var _sample_numbers:Array
    
    public function StssBox() {
        super(BaseMP4.SrsMp4BoxTypeSTSS)
        this._sample_numbers = new Array();
        trace("[stss]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip version, flag   4 bytes
        byte.position += 4
        this._entry_count = byte.readUnsignedInt()
        for (var i:int = 0; i < this._entry_count; i++) {
            var sm:uint = byte.readUnsignedInt()
            this._sample_numbers.push(sm)    
        }
        byte.position = byte.position + byte.bytesAvailable  
    }
    
    public function is_sync(index:uint):Boolean {
        for (var i:int = 0; i < this._entry_count; i++) {
            if (index + 1 == this._sample_numbers[i]) {
                return true
            }
        }
        return false
    }
}

class StsdBox extends Box
{
    private var _entries:Array;
    
    public function StsdBox()
    {
        super(BaseMP4.SrsMp4BoxTypeSTSD)
        this._entries = new Array();
        trace("[stsd]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip version, flag   4 bytes
        byte.position += 4
        var nb_entries:uint = byte.readUnsignedInt();
        
        // read entries
        for (var i:int = 0; i < int(nb_entries); i ++) {
            var box:Box = this.discovery(byte);
            if (box) {
                var d:ByteArray = new ByteArray();
                d.writeBytes(byte, box.position + box.offset, box.size - box.offset);
                d.position = 0;
                box.decode_header(d);
                box.decode_boxes(d);
                byte.position = box.position + box.size;
                
                _entries.push(box);
            }
        }
        byte.position = byte.position + byte.bytesAvailable
    }
    
    public function get avc1():Avc1Box {
        for (var i:int = 0; i < this._entries.length; i++) {
            var box:Box = this._entries[i]
            if (box.type == BaseMP4.SrsMp4BoxTypeAVC1) {
                return Avc1Box(box)
            }
        }
        
        return null
    }
    
    public function get mp4a():Mp4aBox {
        for (var i:int = 0; i < this._entries.length; i++) {
            var box:Box = this._entries[i]
            if (box.type == BaseMP4.SrsMp4BoxTypeMP4A) {
                return Mp4aBox(box)
            }
        }
        
        return null
    }
    
    public function get entries():Array {
        return this._entries
    }
}

class Avc1Box extends Box
{
    private var _width:uint
    private var _heigth:uint
    private var _horizon_resolution:uint
    private var _vert_resolution:uint
    private var _frame_count:uint
    private var _depth:uint
    
    public function Avc1Box()
    {
        super(BaseMP4.SrsMp4BoxTypeAVC1)
        trace("[avc1]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip reserved--6 bytes, data reference--2 bytes
        byte.position += 8
        // skip pre_defined0 2bytes, reserved0 2bytes, predefined1 12bytes
        byte.position += 16
        this._width = byte.readUnsignedShort();
        this._heigth = byte.readUnsignedShort();
        this._horizon_resolution = byte.readUnsignedInt();
        this._vert_resolution = byte.readUnsignedInt();
        // skip reserved1--4bytes, 
        byte.position += 4
        this._frame_count = byte.readUnsignedShort();
        // skip compressor_name--32bytes, 
        byte.position += 32
        this._depth = byte.readUnsignedShort();
        // skip pre_defined2--2bytes
        byte.position += 2
        trace("[avc1]-width:", this._width, "heigth:", this._heigth, "hor_res:", this._horizon_resolution, "vert_res:", this._vert_resolution, "frame_count:", this._frame_count);
    }
    
    public function get avcc():AvccBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeAVCC)
        if (box) {
            return AvccBox(box)
        }
        
        return null
    }
    
    public function get width():uint {
        return this._width
    }
    
    public function get height():uint {
        return this._heigth
    }
}

class AvccBox extends Box
{
    private var _nb_config:uint;
    private var _avc_config:ByteArray = new ByteArray();
    
    public function AvccBox()
    {
        super(BaseMP4.SrsMp4BoxTypeAVCC)
        trace("[avcc]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        this._nb_config = byte.bytesAvailable;
        byte.readBytes(this._avc_config, 0, this._nb_config)
        //this._avc_config.position = 0
        
        byte.position = byte.position + byte.bytesAvailable;
        trace("[avcc]-nb_config", this._nb_config);
    }
    
    public function get avc_config():ByteArray {
        return this._avc_config
    }
}

class Mp4aBox extends Box
{
    private var _channel_count:uint
    private var _sample_size:uint
    private var _sample_rate:uint
    
    public function Mp4aBox()
    {
        super(BaseMP4.SrsMp4BoxTypeMP4A)
        trace("[mp4a]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip reserved--6 bytes, data reference--2 bytes
        byte.position += 8
        // skip reserved0--8 bytes	
        byte.position += 8
        this._channel_count = byte.readUnsignedShort();
        this._sample_size = byte.readUnsignedShort();
        // skip pre_defined0--2bytes, reserved1 2bytes
        byte.position += 4
        this._sample_rate = byte.readUnsignedShort();	
        byte.position += 2
        
        //byte.position = byte.position + byte.bytesAvailable;
        trace("[mp4a:channel-]", this._channel_count, "sample size-", this._sample_size, "sample rate:", this._sample_rate, "bytes avaliable:", byte.bytesAvailable);	
    }
    
    public function get esds():EsdsBox {
        var box:Box = this.getBox(BaseMP4.SrsMp4BoxTypeESDS)
        if (box) {
            return EsdsBox(box)
        }
        return null
    }
    
    public function get asc():Mp4DecoderSpecificInfo {
        var box:EsdsBox = this.esds
        if (box) {
            return box.asc
        }
        return null
    }
    
    public function get sample_rate():uint {
        return this._sample_rate
    }
    
    public function get sample_size():uint {
        return this._sample_size
    }
    
    public function get channel_count():uint {
        return this._channel_count
    }
}

class EsdsBox extends Box
{
    private var _version:uint;
    private var _flags:uint;
    private var _es:Mp4ES_Descriptor
    
    public function EsdsBox()
    {
        super(BaseMP4.SrsMp4BoxTypeESDS)
        trace("[esds]");
        _es = new Mp4ES_Descriptor()
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // mp4 full box
        // read tag, version
        _flags = byte.readUnsignedInt();
        _version = (_flags >> 24)& 0xff;
        _flags = _flags & 0x00ffffff
        
        // es decode
        _es.decode(byte)    
        byte.position = byte.position + byte.bytesAvailable;
    }
    
    public function get asc():Mp4DecoderSpecificInfo {
        return this._es.decConfigDescr.descSpecificInfo
    }
}

class Mp4ES_Descriptor {
    private var _base:Mp4BaseDescriptor
    private var _ES_ID:uint // bit(16)
    private var _streamDependenceFlag:uint // bit(1)
    private var _URL_Flag:uint // bit(1)
    private var _OCRstreamFlag:uint // bit(1)
    private var _streamPriority:uint // bit(5)
    //if _streamDependenceFlag
    private var _dependsOn_ES_ID:uint // bit(16), 
    // if URL_Flag
    private var _URLlength:uint // bit(8)
    private var _URLstring:ByteArray
    // if (OCRstreamFlag)
    private var _OCR_ES_Id:uint // bit(16)
    
    public var decConfigDescr:Mp4DecoderConfigDescriptor
    public var slConfigDescr:Mp4SLConfigDescriptor
    
    
    public function Mp4ES_Descriptor():void {
        _base = new Mp4BaseDescriptor();
        this._URLstring = new ByteArray()
        decConfigDescr = new Mp4DecoderConfigDescriptor()   
        slConfigDescr = new Mp4SLConfigDescriptor()    
    }
    
    public function decode(byte:ByteArray):void {
        _base.decode_header(byte)
        _ES_ID = _base.readUnsigendShort(byte);
        
        var data:uint = _base.readUnsigendByte(byte);
        _streamPriority = data & 0x1f
        _streamDependenceFlag = (data >> 7) & 0x01
        _URL_Flag = (data >> 6) & 0x01
        _OCRstreamFlag = (data >> 5) & 0x01
        
        if (this._streamDependenceFlag == 0x01) {
            this._dependsOn_ES_ID = _base.readUnsigendShort(byte);
        }
        if (this._URL_Flag == 0x01) {
            this._URLlength = _base.readUnsigendByte(byte);
            _base.readBytes(byte, this._URLlength, this._URLstring)
        }
        if (this._OCRstreamFlag) {
            this._OCR_ES_Id = _base.readUnsigendShort(byte)
        }
        
        this.decConfigDescr.decode(byte)
        this.slConfigDescr.decode(byte)    
    }
}

/**
 * 7.2.6.7 DecoderSpecificInfo
 * ISO_IEC_14496-1-System-2010.pdf, page 51
 */
class Mp4DecoderSpecificInfo {
    private var _base:Mp4BaseDescriptor
    public var asc:ByteArray
    
    public function Mp4DecoderSpecificInfo():void {
        _base = new Mp4BaseDescriptor()
        asc = new ByteArray()
    }
    
    public function decode(byte:ByteArray):void {
        _base.decode_header(byte)
        _base.readBytes(byte, _base.vlen, asc)
        asc.position = 0    
        trace("decode specificInfo:asc:", asc.bytesAvailable, asc.length)    
    }
}

/**
 * 7.2.6.6 DecoderConfigDescriptor
 * ISO_IEC_14496-1-System-2010.pdf, page 48
 */
class Mp4DecoderConfigDescriptor {
    private var _base:Mp4BaseDescriptor
    
    // an indication of the object or scene description type that needs to be supported
    // by the decoder for this elementary stream as per Table 5.
    private var _objectTypeIndication:uint // bit(8)
    private var _streamType:uint // bit(6)
    private var _upStream:uint // bit(1)
    private var _reserved:uint // bit(1)
    private var _bufferSizeDB:uint // bit(24)
    private var _maxBitrate:uint
    private var _avgBitrate:uint
    
    public var descSpecificInfo:Mp4DecoderSpecificInfo
    
    public function Mp4DecoderConfigDescriptor():void {
        _base = new Mp4BaseDescriptor();
        descSpecificInfo = new Mp4DecoderSpecificInfo()
    }
    
    public function decode(byte:ByteArray):void {
        _base.decode_header(byte)
        this._objectTypeIndication = _base.readUnsigendByte(byte)
        var data:uint = _base.readUnsigendByte(byte)
        
        this._upStream = (data >> 1) & 0x01
        this._streamType = (data >> 2) & 0x3f
        this._reserved = data & 0x01            
        
        var tmp:ByteArray = new ByteArray()
        _base.readBytes(byte, 3, tmp)
        //TODO: convert tmp 3bytes to buffersizedb    
        
        this._maxBitrate = _base.readUnsignedInt(byte)   
        this._avgBitrate = _base.readUnsignedInt(byte)
        
        trace("after decode DecoderConfigDescriptor, left:", _base.left);
        if (_base.left > 0) {
            this.descSpecificInfo.decode(byte)
        }
    }
}

class Mp4SLConfigDescriptor {
    private var _base:Mp4BaseDescriptor 
    private var _predefined:uint
    
    public function Mp4SLConfigDescriptor():void {
        _base = new Mp4BaseDescriptor();
    }
    
    public function decode(byte:ByteArray):void {
        _base.decode_header(byte)
        this._predefined = _base.readUnsigendByte(byte)    
    }
}

import flash.utils.ByteArray;

class Mp4BaseDescriptor {
    private var _tag:uint
    private var _vlen:uint
    private var _total:uint
    private var _used:uint
    
    public function Mp4BaseDescriptor() {
        
    }
    
    public function decode_header(byte:ByteArray):void {
        _tag = byte.readUnsignedByte()
        _total += 1
        
        var vsize:uint
        var length:uint = 0
        
        while (true) {
            vsize = byte.readUnsignedByte()
            length = (length << 7) || (vsize & 0x7f)
            _total += 1
            if ((vsize & 0x80) != 0x80) {
                break
            }
        }
        
        _vlen = length;
        _total += length;
    }
    
    public function readUnsigendShort(byte:ByteArray):uint {
        this._used += 2
        return byte.readUnsignedShort()
    }
    
    public function readUnsigendByte(byte:ByteArray):uint {
        this._used += 1
        return byte.readUnsignedByte()
    }
    
    public function readBytes(byte:ByteArray, len:uint, data:ByteArray):void {
        this._used += len
        byte.readBytes(data, 0, len)    
    }
    
    public function readUnsignedInt(byte:ByteArray):uint {
        this._used += 4
        return byte.readUnsignedInt()    
    }
    
    public function get vlen():uint {
        return _vlen;
    }
    
    public function get total():uint {
        return _total;
    }
    
    public function get left():uint {
        return _vlen - _used;
    }
}

/*********************************************************************/
class MdatBox extends Box
{
    public function MdatBox()
    {
        super(BaseMP4.SrsMp4BoxTypeMDAT)
        trace("[mdat]");
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // skip unused bytes
        byte.position = byte.position + byte.bytesAvailable;
        return;
    }
}

class FtypBox extends Box
{
    private var _majorBrand:String;
    private var _minorVersion:uint;
    private var _compatibleBrands:Array;
    
    public function FtypBox()
    {
        super(BaseMP4.SrsMp4BoxTypeFTYP);
    }
    
    override public function decode_header(byte:ByteArray):void
    {
        // ignore read 
        _majorBrand = byte.readUTFBytes(4)
        _minorVersion = byte.readUnsignedInt();
        _compatibleBrands = [];
        while (byte.bytesAvailable >= 4)
        {
            _compatibleBrands.push(byte.readUTFBytes(4));
        }
        
        trace("[ftyp]-majorBrand:" + _majorBrand + "-minorVersion:" + _minorVersion + '-brands: ' + _compatibleBrands);	
    }
    
    public function get majorBrand():String
    {
        return _majorBrand;
    }
    
    public function get minorVersion():uint
    {
        return _minorVersion;
    }
}

/*
* when encounter a unparsed box, can traced as Free box
*/
class FreeBox extends Box
{
    public function FreeBox()
    {
        super(0);
        trace("[Free]");
    }
    override public function decode_header(byte:ByteArray):void
    {
        // skip unused bytes
        byte.position = byte.position + byte.bytesAvailable;
        return;
    }
}

class BaseMP4
{
    public static const SrsMp4BoxTypeUUID:uint = 0x75756964 // 'uuid'
    public static const SrsMp4BoxTypeFTYP:uint = 0x66747970 // 'ftyp'
    public static const SrsMp4BoxTypeMDAT:uint = 0x6d646174 // 'mdat'
    public static const SrsMp4BoxTypeFREE:uint = 0x66726565 // 'free'
    public static const SrsMp4BoxTypeSKIP:uint = 0x736b6970 // 'skip'
    public static const SrsMp4BoxTypeMOOV:uint = 0x6d6f6f76 // 'moov'
    public static const SrsMp4BoxTypeMVHD:uint = 0x6d766864 // 'mvhd'
    public static const SrsMp4BoxTypeTRAK:uint = 0x7472616b // 'trak'
    public static const SrsMp4BoxTypeTKHD:uint = 0x746b6864 // 'tkhd'
    public static const SrsMp4BoxTypeEDTS:uint = 0x65647473 // 'edts'
    public static const SrsMp4BoxTypeELST:uint = 0x656c7374 // 'elst'
    public static const SrsMp4BoxTypeMDIA:uint = 0x6d646961 // 'mdia'
    public static const SrsMp4BoxTypeMDHD:uint = 0x6d646864 // 'mdhd'
    public static const SrsMp4BoxTypeHDLR:uint = 0x68646c72 // 'hdlr'
    public static const SrsMp4BoxTypeMINF:uint = 0x6d696e66 // 'minf'
    public static const SrsMp4BoxTypeVMHD:uint = 0x766d6864 // 'vmhd'
    public static const SrsMp4BoxTypeSMHD:uint = 0x736d6864 // 'smhd'
    public static const SrsMp4BoxTypeDINF:uint = 0x64696e66 // 'dinf'
    public static const SrsMp4BoxTypeURL:uint  = 0x75726c20 // 'url '
    public static const SrsMp4BoxTypeURN:uint  = 0x75726e20 // 'urn '
    public static const SrsMp4BoxTypeDREF:uint = 0x64726566 // 'dref'
    public static const SrsMp4BoxTypeSTBL:uint = 0x7374626c // 'stbl'
    public static const SrsMp4BoxTypeSTSD:uint = 0x73747364 // 'stsd'
    public static const SrsMp4BoxTypeSTTS:uint = 0x73747473 // 'stts'
    public static const SrsMp4BoxTypeCTTS:uint = 0x63747473 // 'ctts'
    public static const SrsMp4BoxTypeSTSS:uint = 0x73747373 // 'stss'
    public static const SrsMp4BoxTypeSTSC:uint = 0x73747363 // 'stsc'
    public static const SrsMp4BoxTypeSTCO:uint = 0x7374636f // 'stco'
    public static const SrsMp4BoxTypeCO64:uint = 0x636f3634 // 'co64'
    public static const SrsMp4BoxTypeSTSZ:uint = 0x7374737a // 'stsz'
    public static const SrsMp4BoxTypeSTZ2:uint = 0x73747a32 // 'stz2'
    public static const SrsMp4BoxTypeAVC1:uint = 0x61766331 // 'avc1'
    public static const SrsMp4BoxTypeAVCC:uint = 0x61766343 // 'avcC'
    public static const SrsMp4BoxTypeMP4A:uint = 0x6d703461 // 'mp4a'
    public static const SrsMp4BoxTypeESDS:uint = 0x65736473 // 'esds'
    public static const SrsMp4BoxTypeUDTA:uint = 0x75647461 // 'udta'
    
    public static const SrsMp4BoxBrandForbidden:uint = 0x00
    public static const SrsMp4BoxBrandISOM:uint = 0x69736f6d // 'isom'
    public static const SrsMp4BoxBrandISO2:uint = 0x69736f32 // 'iso2'
    public static const SrsMp4BoxBrandAVC1:uint = 0x61766331 // 'avc1'
    public static const SrsMp4BoxBrandMP41:uint = 0x6d703431 // 'mp41'
    
    // The type of track, maybe combine of types.
    public static const SrsMp4TrackTypeForbidden:uint = 0x00
    public static const SrsMp4TrackTypeAudio:uint = 0x01
    public static const SrsMp4TrackTypeVideo:uint = 0x02
    
    public static const SrsMp4HandlerTypeForbidden:uint = 0x00
    public static const SrsMp4HandlerTypeVIDE:uint = 0x76696465 // 'vide'
    public static const SrsMp4HandlerTypeSOUN:uint = 0x736f756e // 'soun' 
    
    // set to the zero to reserved, for array map.
    public static const SrsFrameTypeReserved:uint = 0
    public static const SrsFrameTypeForbidden:uint = 0
    
    // 8 = audio
    public static const SrsFrameTypeAudio:uint = 8
    // 9 = video
    public static const SrsFrameTypeVideo:uint = 9
    // 18 = script data
    public static const SrsFrameTypeScript:uint = 18
    
    /**
     * E.4.1 FLV Tag, page 75
     */
    
    public static const SRS_RTMP_TYPE_AUDIO:uint = 8
    public static const SRS_RTMP_TYPE_VIDEO:uint = 9
    public static const SRS_RTMP_TYPE_SCRIPT:uint = 18 
    
    /**
     * The audio sample rate.
     * @see srs_flv_srates and srs_aac_srates.
     * @doc video_file_format_spec_v10_1.pdf, page 76, E.4.2 Audio Tags
     *      0 = 5.5 kHz = 5512 Hz
     *      1 = 11 kHz = 11025 Hz
     *      2 = 22 kHz = 22050 Hz
     *      3 = 44 kHz = 44100 Hz
     * However, we can extends this table.
     */    
    public static const SrsAudioSampleRate5512:uint = 0
    public static const SrsAudioSampleRate11025:uint = 1
    public static const SrsAudioSampleRate22050:uint = 2
    public static const SrsAudioSampleRate44100:uint = 3   
    
    /**
     * The audio sample size in bits.
     * @doc video_file_format_spec_v10_1.pdf, page 76, E.4.2 Audio Tags
     * Size of each audio sample. This parameter only pertains to
     * uncompressed formats. Compressed formats always decode
     * to 16 bits internally.
     *      0 = 8-bit samples
     *      1 = 16-bit samples
     */
    public static const SrsAudioSampleBits8bit:uint = 0
    public static const SrsAudioSampleBits16bit:uint = 1 
    
    /**
     * The audio channels.
     * @doc video_file_format_spec_v10_1.pdf, page 77, E.4.2 Audio Tags
     * Mono or stereo sound
     *      0 = Mono sound
     *      1 = Stereo sound
     */    
    public static const SrsAudioChannelsMono:uint = 0
    public static const SrsAudioChannelsStereo:uint = 1  
    
    // set to the zero to reserved, for array map.
    public static const SrsVideoCodecIdReserved:uint = 0
    public static const SrsVideoCodecIdForbidden:uint = 0
    public static const SrsVideoCodecIdReserved1:uint = 1
    public static const SrsVideoCodecIdReserved2:uint = 9
    
    // for user to disable video, for example, use pure audio hls.
    public static const SrsVideoCodecIdDisabled:uint = 8
    
    public static const SrsVideoCodecIdSorensonH263:uint = 2
    public static const SrsVideoCodecIdScreenVideo:uint = 3
    public static const SrsVideoCodecIdOn2VP6:uint = 4
    public static const SrsVideoCodecIdOn2VP6WithAlphaChannel:uint = 5
    public static const SrsVideoCodecIdScreenVideoVersion2:uint = 6
    public static const SrsVideoCodecIdAVC:uint = 7  
    
    // set to the max value to reserved, for array map.
    public static const SrsAudioCodecIdReserved1:uint = 16
    public static const SrsAudioCodecIdForbidden:uint = 16
    
    // for user to disable audio, for example, use pure video hls.
    public static const SrsAudioCodecIdDisabled:uint = 17
    
    public static const SrsAudioCodecIdLinearPCMPlatformEndian:uint = 0
    public static const SrsAudioCodecIdADPCM:uint = 1
    public static const SrsAudioCodecIdMP3:uint = 2
    public static const SrsAudioCodecIdLinearPCMLittleEndian:uint = 3
    public static const SrsAudioCodecIdNellymoser16kHzMono:uint = 4
    public static const SrsAudioCodecIdNellymoser8kHzMono:uint = 5
    public static const SrsAudioCodecIdNellymoser:uint = 6
    public static const SrsAudioCodecIdReservedG711AlawLogarithmicPCM:uint = 7
    public static const SrsAudioCodecIdReservedG711MuLawLogarithmicPCM:uint = 8
    public static const SrsAudioCodecIdReserved:uint = 9
    public static const SrsAudioCodecIdAAC:uint = 10
    public static const SrsAudioCodecIdSpeex:uint = 11
    public static const SrsAudioCodecIdReservedMP3_8kHz:uint = 14
    public static const SrsAudioCodecIdReservedDeviceSpecificSound:uint = 15  
    
    /**
     * The video AVC frame type, such as I/P/B.
     * @doc video_file_format_spec_v10_1.pdf, page78, E.4.3.1 VIDEODATA
     * Frame Type UB [4]
     * Type of video frame. The following values are defined:
     *      1 = key frame (for AVC, a seekable frame)
     *      2 = inter frame (for AVC, a non-seekable frame)
     *      3 = disposable inter frame (H.263 only)
     *      4 = generated key frame (reserved for server use only)
     *      5 = video info/command frame
     */
    // set to the zero to reserved, for array map.
    public static const SrsVideoAvcFrameTypeReserved:uint = 0
    public static const SrsVideoAvcFrameTypeForbidden:uint = 0
    public static const SrsVideoAvcFrameTypeReserved1:uint = 6
    
    public static const SrsVideoAvcFrameTypeKeyFrame:uint = 1
    public static const SrsVideoAvcFrameTypeInterFrame:uint = 2
    public static const SrsVideoAvcFrameTypeDisposableInterFrame:uint = 3
    public static const SrsVideoAvcFrameTypeGeneratedKeyFrame:uint = 4
    public static const SrsVideoAvcFrameTypeVideoInfoFrame:uint = 5 
    
    /**
     * The video AVC frame trait(characteristic).
     * @doc video_file_format_spec_v10_1.pdf, page79, E.4.3.2 AVCVIDEOPACKET
     * AVCPacketType IF CodecID == 7 UI8
     * The following values are defined:
     *      0 = AVC sequence header
     *      1 = AVC NALU
     *      2 = AVC end of sequence (lower level NALU sequence ender is not required or supported)
     */
    // set to the max value to reserved, for array map.
    public static const SrsVideoAvcFrameTraitReserved:uint = 3
    public static const SrsVideoAvcFrameTraitForbidden:uint = 3
    
    public static const SrsVideoAvcFrameTraitSequenceHeader:uint = 0
    public static const SrsVideoAvcFrameTraitNALU:uint = 1
    public static const SrsVideoAvcFrameTraitSequenceHeaderEOF:uint = 2 
    
    /**
     * The audio AAC frame trait(characteristic).
     * @doc video_file_format_spec_v10_1.pdf, page 77, E.4.2 Audio Tags
     * AACPacketType IF SoundFormat == 10 UI8
     * The following values are defined:
     *      0 = AAC sequence header
     *      1 = AAC raw
     */
    // set to the max value to reserved, for array map.
    public static const SrsAudioAacFrameTraitReserved:uint = 2
    public static const SrsAudioAacFrameTraitForbidden:uint = 2
    
    public static const SrsAudioAacFrameTraitSequenceHeader:uint = 0
    public static const SrsAudioAacFrameTraitRawData:uint = 1 
    
    public static const AMF_DATA_TYPE_NUMBER:uint = 0
    public static const AMF_DATA_TYPE_BOOLEAN:uint = 1
    public static const AMF_DATA_TYPE_STRING:uint = 2
    
    public static const AMF_DATA_TYPE_Reference:uint = 7
    public static const AMF_DATA_TYPE_ECMA_array:uint = 8    
    
    public function BaseMP4()
    {
    }
    
    /**
     *
     * @param type
     * @return Box
     */
    public static function getBox(type:uint):Box
    {
        var box:Box = null;
        switch(type)
        {
            case SrsMp4BoxTypeFTYP:
                box = new FtypBox();
                break;
            case SrsMp4BoxTypeMOOV:
                box = new MoovBox();
                break;
            case SrsMp4BoxTypeMDAT:
                box = new MdatBox();
                break;
            //
            case SrsMp4BoxTypeMVHD:
                box = new MvhdBox();
                break;
            case SrsMp4BoxTypeTRAK:
                box = new TracBox();
                break;
            case SrsMp4BoxTypeTKHD:
                box = new TkhdBox();
                break;
            case SrsMp4BoxTypeMDIA:
                box = new MdiaBox();
                break;
            case SrsMp4BoxTypeMDHD:
                box = new MdhdBox();
                break;
            case SrsMp4BoxTypeHDLR:
                box = new HdlrBox();
                break;
            case SrsMp4BoxTypeMINF:
                box = new MinfBox();
                break;
            case SrsMp4BoxTypeSTBL:
                box = new StblBox();
                break;
            case SrsMp4BoxTypeSTSD:
                box = new StsdBox();
                break;
            case SrsMp4BoxTypeMP4A:
                box = new Mp4aBox();
                break;
            case SrsMp4BoxTypeAVC1:
                box = new Avc1Box();
                break;
            case SrsMp4BoxTypeAVCC:
                box = new AvccBox();
                break;
            case SrsMp4BoxTypeESDS:
                box = new EsdsBox();
                break;
            case SrsMp4BoxTypeSTCO:
                box = new StcoBox()
                break;
            case SrsMp4BoxTypeSTSZ:
                box = new StszBox()
                break;
            case SrsMp4BoxTypeSTSC:
                box = new StscBox()
                break;
            case SrsMp4BoxTypeSTTS:
                box = new SttsBox()
                break;
            case SrsMp4BoxTypeCTTS:
                box = new CttsBox()
                break;
            case SrsMp4BoxTypeSTSS:
                box = new StssBox()
                break;
            default :
                trace('[MP4::getBox] 0x' + type.toString(16) + ' not defined.');
                box = new FreeBox();
                
        }
        return box;
    }
}