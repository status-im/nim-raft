import asyncio
import tornado
import os
import sys
import errno
import msgpack

writeFIFO = 'RAFTNODERECEIVEMSGPIPE'
readFIFO = 'RAFTNODESENDMSGRESPPIPE'

def writeFifo(data):
    with open(writeFIFO, "ab") as fw:
        fw.write(data)
        
def readPipe():
    while True:
        with open(readFIFO, "rb") as fifo:
            data = fifo.read()
                # writeFifo(data)
            if len(data) == 0:
                pass
                # print("Writer closed")
            else:
                print('Read: {0}'.format(data))
                return data

class MainHandler(tornado.web.RequestHandler):
    def post(self):
        s = self.request.body
        print(s)
        writeFifo(s)
        r = readPipe()
        print(r)
        self.write(r)

    def get(self):
        self.write("Hello, world")

def make_app():
   
    return tornado.web.Application([
        (r"/", MainHandler),
    ])

async def main():
    if len(sys.argv) < 2:
        print("Usage: tornado_simple_raft_node_server.py <port>")
        return
    app = make_app()
    app.listen(int(sys.argv[1]))
    await asyncio.Event().wait()

if __name__ == "__main__":
    try:
        readFIFO = readFIFO + sys.argv[1]
        writeFIFO = writeFIFO + sys.argv[1]
        os.mkfifo(readFIFO)
        os.mkfifo(writeFIFO)
    except OSError as oe: 
        if oe.errno != errno.EEXIST:
            raise
    
    # readPipe()
    
    asyncio.run(main())
                