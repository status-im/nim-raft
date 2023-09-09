import asyncio
import tornado
import os
import sys
import errno
import msgpack

writeFIFO = '/home/raych/prg/nim-raft/RAFTNODESENDMSGRESPPIPE'
readFIFO = '/home/raych/prg/nim-raft/RAFTNODERECEIVEMSGPIPE'

def writeFifo(data):
    with open(writeFIFO, "a") as fw:
        fw.write(data)
        
def readPipe():
    with open(readFIFO, "r") as fifo:
            data = fifo.read()
            if len(data) == 0:
                pass
                # print("Writer closed")
            else:
                print('Read: {0}'.format(data))
                return data

class MainHandler(tornado.web.RequestHandler):
    def post(self):
        s = self.request.body.decode("utf-8")
        print(s)
        writeFifo(s)
        self.write(msgpack.dumps(readPipe()))

    def get(self):
        self.write("Hello, world")

def make_app():
   
    return tornado.web.Application([
        (r"/", MainHandler),
    ])

async def main():
    if len(sys.argv) < 2:
        print("Usage: tornado_simple_raft_node_server.py <port>")
        shutdown_event.set()
        return
    app = make_app()
    app.listen(int(sys.argv[1]))
    await asyncio.Event().wait()

if __name__ == "__main__":
    try:
        os.mkfifo(readFIFO)
        os.mkfifo(writeFIFO)
    except OSError as oe: 
        if oe.errno != errno.EEXIST:
            raise
    
    asyncio.run(main())
                