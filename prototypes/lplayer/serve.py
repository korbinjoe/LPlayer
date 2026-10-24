from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import os,re
os.chdir(Path(__file__).resolve().parent)
class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path=self.translate_path(self.path)
        if 'Range' not in self.headers or not os.path.isfile(path):
            return super().do_GET()
        size=os.path.getsize(path)
        match=re.match(r'bytes=(\d*)-(\d*)',self.headers['Range'])
        if not match:return super().do_GET()
        start=int(match[1] or 0);end=min(int(match[2]) if match[2] else size-1,size-1)
        if start>size-1 or start>end:
            self.send_response(416);self.send_header('Content-Range',f'bytes */{size}');self.end_headers();return
        self.send_response(206);self.send_header('Content-Type',self.guess_type(path));self.send_header('Content-Range',f'bytes {start}-{end}/{size}');self.send_header('Content-Length',str(end-start+1));self.send_header('Accept-Ranges','bytes');self.end_headers()
        try:
            with open(path,'rb') as f:
                f.seek(start);remaining=end-start+1
                while remaining:
                    chunk=f.read(min(65536,remaining))
                    if not chunk:break
                    self.wfile.write(chunk);remaining-=len(chunk)
        except (BrokenPipeError,ConnectionResetError):pass
    def end_headers(self):
        self.send_header('Cache-Control','no-cache')
        super().end_headers()
    def log_message(self,*args):pass
print('LPlayer visual prototype: http://127.0.0.1:4178',flush=True)
ThreadingHTTPServer(('127.0.0.1',4178),Handler).serve_forever()
