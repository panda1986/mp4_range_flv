package socket
{
    import com.adobe.net.URI;
    
    import flash.display.Sprite;
    import flash.errors.IOError;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.Socket;
    import flash.net.URLRequestHeader;
    import flash.utils.ByteArray;
    
    import mx.utils.StringUtil;
    
    public class BravoSocket extends EventDispatcher
    {
        private var _socket:Socket;
        private var _uri:URI;
        private var _host:String;
        private var _port:uint;
        
        // socket request header byte array, to parse range params
        private var _header_byte_array:ByteArray;
        // socket request body byte array, the real file data
        private var _body_byte_array:ByteArray;
        // socket request total byte array
        private var _tmp_byte_array:ByteArray;
        
        // socket header status array, if null, it's first req
        private var _http_status:Array;
        private var _keep_alive:Boolean;
        private var _byte_total:uint;
        private var _byte_start:uint;
        private var _byte_end:uint;
        private var _byte_required:uint;
        
        private var _http_code:int;
        
        public static const Evt_SocketloadDone:String = "Evt_SocketloadDone";
        public static const Evt_SocketConnect:String = "Evt_SocketConnect";
        
        public function BravoSocket(url:String)
        {
            super();
            
            _socket = new Socket();
            _uri = new URI(url);
            _header_byte_array = new ByteArray();
            _body_byte_array = new ByteArray();
            _tmp_byte_array = new ByteArray();
            _http_code = -1;
            
            _socket.addEventListener(Event.CLOSE, closeHandler);
            _socket.addEventListener(Event.CONNECT, connectHandler);
            _socket.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
            _socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
            _socket.addEventListener(ProgressEvent.SOCKET_DATA, socketDataHandler);
            
            init();  
            connect();
        }
        
        private function connect():void {
            this._socket.connect(_host, _port);
            trace("connecting to", _host, "port:", _port);
        }
        
        private function init():void {
            if (this._uri.port == "") {
                this._port = 80;
            }
            this._host = this._uri.authority;
            trace(this._uri.authority);
        }
        
        protected var _header:Object = {
            'User-Agent' : 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:17.0) Gecko/20100101 Firefox/17.0',
            'Connection' : 'keep-alive',
            'Accept' : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Encoding' : 'gzip, deflate',
            'Accept-Language' : 'zh-cn,zh;q=0.8,en-us;q=0.5,en;q=0.3',
            'Host': _host
        };
        
        private function get requestHeader():String{
            var query:Array = ["GET "+this._uri.path + (this._uri.query ? ( '?' + this._uri.query ) : '') +" HTTP/1.1"];
            for(var key:String in this._header){
                if(this._header.hasOwnProperty(key)){
                    query.push(key + ": " + this._header[key]);
                }
            }
            return query.join("\r\n") + "\r\n\r\n";
        }
        
        public function send(start:uint, end:uint):Boolean{
            trace("send start " + start + ", end = " + end)
            if(this._byte_total > 0 && start >= this._byte_total) return false;
            this._header_byte_array.clear();
            this._body_byte_array.clear();
            this._tmp_byte_array.clear();
            this._http_status = null;
            this._http_code = -1;
            this._byte_required = end - start + 1;
            
            try{
                //这个是最重要的
                this._header['Range'] = "bytes="+start+"-" + (this._byte_total > 0 ? Math.min(end, this._byte_total - 1)  : end);
                this._header['Host'] = _host;
                trace("header", this.requestHeader);
                this._socket.writeUTFBytes(this.requestHeader);
                this._socket.flush();
                
            }catch(e:Error){
                return false;
            }
            return true;
        }
        
        private function closeHandler(event:Event):void {
            trace("closeHandler: " + event);
        }
        
        private function connectHandler(event:Event):void {
            trace("connectHandler: " + event);
            this.dispatchEvent(new Event(Evt_SocketConnect));
        }
        
        private function ioErrorHandler(event:IOErrorEvent):void {
            trace("ioErrorHandler: " + event);
        }
        
        private function securityErrorHandler(event:SecurityErrorEvent):void {
            trace("securityErrorHandler: " + event);
        }
        
        private function socketDataHandler(event:ProgressEvent):void {
            //trace("socketDataHandler: " + event, event);
            this._socket.readBytes(this._tmp_byte_array, 0, event.bytesLoaded);
            
            //如果还未发现完整的http header 信息
            if(this._http_status === null){  
                //把上次从socket获取的数据读出来
                this._header_byte_array.position = this._header_byte_array.length;
                this._header_byte_array.writeBytes(this._tmp_byte_array);
                this._header_byte_array.position = 0;
                this._tmp_byte_array.clear();    
                
                var value:String = String(_header_byte_array.readUTFBytes(_header_byte_array.bytesAvailable))
                var index:int = value.indexOf("\r\n\r\n")
                
                //获取的数据，header还没有完全
                if(index == -1){        
                    return;
                }
                
                //获取数据中除去header之外的数据，就是我们想要的
                _header_byte_array.position = 0;
                this._body_byte_array.clear();
                this._body_byte_array.writeBytes(_header_byte_array, index+4, _header_byte_array.bytesAvailable - (index + 4)); 
                
                //解析http header
                var header:String = value.substr(0, index+4);
                var array:Array = header.match(/HTTP\/1\.\d (\d{3})/i);
                var regexp:RegExp = /([a-z0-9\-]{1,64}): (.*)/ig;
                var map:Array = null;
                var param:Object = {};
                
                this._http_status = new Array();
                
                while(map = regexp.exec(header)){
                    this._http_status.push(new URLRequestHeader(map[1], map[2]));        
                    param[String(map[1]).toLowerCase()] = StringUtil.trim(String(map[2]));
                } 
                
                //判断服务器是否支持 keepalive，如果支持的话，那就不用每次都建立连接了
                if(!param.hasOwnProperty('connection') || param['connection'] == 'close') 
                    this._keep_alive = false;
                else 
                    this._keep_alive = true;
                
                //分析服务器返回的 content-range，可以知道服务器返回的是哪部分数据
                if(typeof param['content-range'] != 'undefined'){
                    var range:String = StringUtil.trim(String(param['content-range']));
                    var match:Array = range.match(/([0-9]{1,9})\-([0-9]{1,9})\/([0-9]{1,9})/i);
                    if(match){
                        this._byte_total = uint(match[3]);
                        this._byte_start = uint(match[1]);
                        this._byte_end = uint(match[2]);
                    }else{
                        this._byte_total = 0;
                    }
                }
                
                if(!array){
                    this._socket.close();
                    return;
                }
                
                var code:uint = uint(array[1]);
                if(code == 301 || code == 302){
                    //这里需要重定向
                    trace("here need redirect");
                    this._socket.close();
                    return;
                }
                
                if(code >= 400){
                    //服务器有问题等...
                    trace("may be some error occurs in server");
                    this._socket.close();
                    return;
                }
                
                if(this._http_code == -1 && array && uint(array[1]) > 0){
                    this._http_code = uint(array[1]);
                }
            } else{
                this._body_byte_array.position = this._body_byte_array.length;
                this._body_byte_array.writeBytes(this._tmp_byte_array);
                this._tmp_byte_array.clear();
            }
            
            if (this._body_byte_array.length >= this._byte_required) {
                this.dispatchEvent(new Event(Evt_SocketloadDone));
            }
        }
        
        public function get body():ByteArray {
            return this._body_byte_array;
        }
        
        public function get total():uint {
            return this._byte_total;
        }
    }
}