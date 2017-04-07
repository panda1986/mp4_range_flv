package
{
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.NetStatusEvent;
    import flash.media.Video;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.net.NetStreamAppendBytesAction;
    import flash.utils.ByteArray;
    
    import mp4.MP4;
    
    import socket.BravoSocket;
    
    public class Mp4RangeFlv extends Sprite
    {
        private var video:Video;
        private var video_nc:NetConnection;
        private var video_ns:NetStream;
        private var mp4_url:String = "http://gitdown.bravovcloud.com/video/3.mp4";
        private var _mp4:MP4
        private var _phase:uint
        private var _piece:FlvPiece;
        
        public static const get_moov_size_phase:uint = 0
        public static const get_moov_phase:uint = 1
        public static const get_flv_tag:uint = 2 
        public static const PerPieceSeconds:uint = 3    
        
        public function Mp4RangeFlv()
        {
            super();
            
            video = new Video();
            video_nc = new NetConnection();
            video_nc.connect(null);
            video_ns = new NetStream(video_nc);
            _mp4 = new MP4();
            _phase = Mp4RangeFlv.get_moov_size_phase;   
            
            var onMetaData1:Function = function(info:Object):void {
                video.x = 0;
                video.y = 0;
                video.width = 320;
                video.height = 240;
                trace("metadata2: duration=" + info.duration + " width=" + info.width + 
                    " height=" + info.height + "x=" + video.x + "y=" + video.y);
                
            };
            video_ns.client = { onMetaData : onMetaData1 };
            video_ns.addEventListener(NetStatusEvent.NET_STATUS, ns_statusHandler);
            
            video.attachNetStream(video_ns);
            video.smoothing = true;
            
            video_ns.play(null);
            video_ns.appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN);
            
            addChild(video);
            
            var bs:BravoSocket = new BravoSocket(mp4_url);
            
            bs.addEventListener(BravoSocket.Evt_SocketConnect, function(e:Event):void{
                bs.send(0,99)
            })
            bs.addEventListener(BravoSocket.Evt_SocketloadDone, function(e:Event):void{
                trace("load range data success", bs.total, bs.body.length, bs.body.bytesAvailable)
                if (_phase == Mp4RangeFlv.get_moov_size_phase) {
                    _mp4.parse_moov_size(bs.body)
                    if (_mp4.moov_start <= 0 || _mp4.moov_end <= 0) {
                        trace("parse moov size failed, start=", _mp4.moov_start, "end=", _mp4.moov_end)
                        return;
                    }
                    _phase = Mp4RangeFlv.get_moov_phase;
                    bs.send(_mp4.moov_start, _mp4.moov_end);
                    return;
                }
                if (_phase == Mp4RangeFlv.get_moov_phase) {
                    _mp4.parse_moov(bs.body);
                    var sh:ByteArray = _mp4.parse_sequence_header();
                    video_ns.appendBytes(sh);
                    
                    _phase = Mp4RangeFlv.get_flv_tag;
                    _piece = new FlvPiece(0)
                    var range:Object = _mp4.parse_piece_range(_piece.piece_id);
                    _piece.start_sid = range.st_sid;
                    _piece.end_sid = range.end_sid;
                    
                    trace("range st=", _mp4.get_sample_offset(_piece.start_sid), "end=", _mp4.get_sample_offset(_piece.end_sid));
                    bs.send(_mp4.get_sample_offset(_piece.start_sid), _mp4.get_sample_offset(_piece.end_sid));
                    return;
                }
                if (_phase == Mp4RangeFlv.get_flv_tag) {
                    // encode piece to flv tag
                    var data:ByteArray = _mp4.parse_piece(bs.body, _piece.start_sid, _piece.end_sid);
                    video_ns.appendBytes(data);
                    
                    // piece id ++
                    _piece.piece_id += 1;
                    // continue to next
                    range = _mp4.parse_piece_range(_piece.piece_id);
                    if (range.st_sid && range.end_sid) {
                        _piece.start_sid = range.st_sid;
                        _piece.end_sid = range.end_sid;
                        
                        trace("range st=", _piece.start_sid, "end=", _piece.end_sid, "piece id=", _piece.piece_id);
                        trace("range st=", _mp4.get_sample_offset(_piece.start_sid), "end=", _mp4.get_sample_offset(_piece.end_sid));
                        bs.send(_mp4.get_sample_offset(_piece.start_sid), _mp4.get_sample_offset(_piece.end_sid));
                    }
                }
            })
        }
        
        private function ns_statusHandler(event:NetStatusEvent):void
        {
            trace(event.info.code);
        }
    }
}

class FlvPiece {
    private var _piece_id:uint;
    private var _start_sid:uint;
    private var _end_sid:uint;
    
    public function FlvPiece(piece_id:uint) {
        _piece_id = piece_id;
    }
    
    public function get piece_id():uint {
        return _piece_id;
    }
    
    public function set piece_id(id:uint):void {
        _piece_id = id;
    }
    
    public function get start_sid():uint {
        return _start_sid;
    }
    
    public function set start_sid(id:uint):void {
        _start_sid = id;
    }
    
    public function get end_sid():uint {
        return _end_sid;
    }
    
    public function set end_sid(id:uint):void {
        _end_sid = id;
    }
}