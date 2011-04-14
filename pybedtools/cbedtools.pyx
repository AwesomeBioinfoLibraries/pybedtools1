"""
    bedtools.pyx: A Cython wrapper for the BEDTools BedFile class
    
    Authors: Aaron Quinlan[1], Brent Pedersen[2]
    Affl:    [1] Center for Public Health Genomics, University of Virginia
             [2] 
    Email:  aaronquinlan at gmail dot com
"""
include "cbedtools.pxi"
from cython.operator cimport dereference as deref

cdef class Interval:
    cdef BED *_bed

    def __init__(self, chrom, start, end, strand = None):
        if strand is None:
            self._bed = new BED(string(chrom), start, end)
        else:
            self._bed = new BED(string(chrom), start, end, string(strand))


    def get_chrom(self):
        return self._bed.chrom.c_str()
    def set_chrom(self, chrom):
        self._bed.chrom = string(chrom)
    chrom = property(get_chrom, set_chrom)

    def get_start(self):
        return self._bed.start
    def set_start(self, int start):
        self._bed.start = start
    start = property(get_start, set_start)

    def get_end(self):
        return self._bed.end
    def set_end(self, int end):
        self._bed.end = end
    stop = end = property(get_end, set_end)

    # TODO: make this more robust.
    @property
    def count(self):
        return int(self.other[-1])

    @property
    def name(self):
        return self._bed.name.c_str()

    @property
    def score(self):
        return self._bed.score.c_str()

    @property
    def strand(self):
        return self._bed.strand.c_str()

    @property
    def other(self):
        return string_vec2list(self._bed.otherFields)

    @property
    def length(self):
        return self._bed.end - self._bed.start

    # TODO: maybe bed.overlap_start or bed.overlap.start ??
    @property
    def o_start(self):
        return self._bed.o_start

    @property
    def o_end(self):
        return self._bed.o_end

    @property
    def o_amt(self):
        return self._bed.o_end - self._bed.o_start

    def __str__(self):
        return self._bed.reportBed().c_str()

    def __repr__(self):
        return "Interval(%s:%i-%i)" % (self.chrom, self.start, self.end)

    def __dealloc__(self):
        del self._bed

    def __getitem__(self, object key):
        cdef int i
        if isinstance(key, (int, long)):
            return self._bed.fields.at(key).c_str()
        elif isinstance(key, slice):
            #sys.stderr.write(key)
            return [self._bed.fields.at(i).c_str() for i in \
                    range(key.start or 0,
                          key.stop or self._bed.fields.size(),
                          key.step or 1)]

        elif isinstance(key, basestring):
            raise Exception("unimplemented")


cdef Interval create_interval(BED b):
    cdef Interval pyb = Interval.__new__(Interval)
    pyb._bed = new BED(b.chrom, b.start, b.end, b.name,
                       b.score, b.strand, b.otherFields,
                       b.o_start, b.o_end, b.bedType, b.isGff, b.isVcf, b.status)
    pyb._bed.fields = b.fields
    return pyb

cdef Interval create_interval_from_list(list fields):
    cdef Interval pyb = Interval.__new__(Interval)
    pyb._bed = new BED(string(fields[0]), int(fields[1]), int(fields[2]), string(fields[3]),
                       string(fields[4]), string(fields[5]), list_to_vector(fields[6]))
    return pyb

cdef vector[string] list_to_vector(list li):
    cdef vector[string] s
    cdef int i
    for i in range(len(li)):
        s.push_back(string(li[i]))
    return s



cdef list string_vec2list(vector[string] sv):
    cdef size_t size = sv.size(), i
    cdef list l = []
    for i in range(size):
        l.append(sv.at(i).c_str())
    return l

cdef list bed_vec2list(vector[BED] bv):
    cdef size_t size = bv.size(), i
    cdef list l = []
    cdef BED b
    for i in range(size):
        b = bv.at(i)
        l.append(create_interval(b))
    return l


def overlap(int s1, int s2, int e1, int e2):
    return min(e1,e2) - max(s1,s2)


cdef class IntervalFile:
    cdef BedFile *intervalFile_ptr
    cdef bint _loaded
    cdef bint _open

    def __init__(self, intervalFile):
        self.intervalFile_ptr = new BedFile(string(intervalFile))
        self._loaded = 0
        self._open   = 0

    def __dealloc__(self):
        del self.intervalFile_ptr

    def __iter__(self):
        return self

    def __next__(self):
        if not self._open:
            self.intervalFile_ptr.Open()
            self._open = 1
        cdef BED b = self.intervalFile_ptr.GetNextBed()
        if b.status == BED_VALID:
            return create_interval(b)
        elif b.status == BED_INVALID:
            raise StopIteration
        else:
            return self.next()


    def loadIntoMap(self):
        if self._loaded: return
        self.intervalFile_ptr.loadBedFileIntoMap()
        self._loaded = 1

    def all_hits(self, Interval interval, bool same_strand=False, float overlap=0.0):
        """
        Search for the "bed" feature in this file and ***return all overlaps***
        """
        cdef vector[BED] vec_b
        self.loadIntoMap()

        if same_strand == False:
            vec_b = self.intervalFile_ptr.FindOverlapsPerBin(deref(interval._bed), overlap)
            try:
                return bed_vec2list(vec_b)
            finally:
                pass
        else:
            vec_b = self.intervalFile_ptr.FindOverlapsPerBin(deref(interval._bed), same_strand, overlap)
            try:
                return bed_vec2list(vec_b)
            finally:
                pass

    # search() is an alias for all_hits
    search = all_hits

    def any_hits(self, Interval interval, bool same_strand=False, float overlap=0.0):
        """
        Search for the "bed" feature in this file and return
        whether (True/False) >= 1 overlaps are found.
        """
        found = 0
        self.loadIntoMap()

        if same_strand == False:
            found = self.intervalFile_ptr.FindAnyOverlapsPerBin(deref(interval._bed), overlap)
        else:
            found = self.intervalFile_ptr.FindAnyOverlapsPerBin(deref(interval._bed), same_strand, overlap)

        return found

    def count_hits(self, Interval interval, bool same_strand=False, float overlap=0.0):
        """
        Search for the "bed" feature in this file and return the *** count of hits found ***
        """
        self.loadIntoMap()

        if same_strand == False:
           return self.intervalFile_ptr.CountOverlapsPerBin(deref(interval._bed), overlap)
        else:
           return self.intervalFile_ptr.CountOverlapsPerBin(deref(interval._bed), same_strand, overlap)