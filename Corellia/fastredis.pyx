import redis
import thread
from threading import Semaphore
import time


cdef class Reply(object):
    
    cdef int set
    cdef value
    cdef float interval

    def __cinit__(self, float interval):
        self.set = False
        self.interval = interval

    def set_value(self, value):
        self.value = value
        self.set = True

    def reply(self):
        while not self.set:
            time.sleep(self.interval)
        return self.value

cdef class FastRedis(object):

    cdef redis
    cdef pipeline
    cdef lock
    cdef let
    cdef int empty
    cdef count
    cdef replies
    cdef float interval

    def __cinit__(FastRedis self, char* addr, **kargs):
        if ":" in addr:
            host, port = addr.split(":")
            port = int(port)
        else:
            host = addr
            port = 6379
        self.redis = redis.StrictRedis(host=host, port=port)
        self.pipeline = self.redis.pipeline(transaction=False)
        self.interval = kargs.get("interval", 0.1)
        self.lock = Semaphore()
        self.let= thread.start_new_thread(self.execute, ())
        self.empty = True
        self.replies = []

    cpdef Reply cmd(FastRedis self, char* cmd, tuple args):
        cdef Reply reply = Reply(self.interval)
        self.lock.acquire()
        getattr(self.pipeline, cmd)(*args)
        self.empty = False
        self.replies.append(reply)
        self.lock.release()
        return reply

    cpdef raw_cmd(FastRedis self, char* cmd, tuple args):
        return getattr(self.redis, cmd)(*args)

    cpdef execute(FastRedis self):
        while 1:
            self.submit()
            time.sleep(self.interval)

    cpdef submit(FastRedis self):
        cdef list replies
        self.lock.acquire()
        if not self.empty:
            # print "pipeline...", len(self.replies)
            replies = self.pipeline.execute()
            for i in xrange(len(replies)):
                self.replies[i].set_value(replies[i])
            self.replies = []
            self.empty = True
        self.lock.release()
