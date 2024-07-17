import Vector :: *;
import Settings :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import FIFOF :: *;
import Cntrs :: * ;
import Arbitration :: *;
import PAClib :: *;
import PrimUtils :: *;
import ClientServer :: *;
import Connectable :: *;
import GetPut :: *;
import ConfigReg :: * ;
import Randomizable :: *;
import PrimUtils :: *;
import RdmaUtils :: *;

import ConnectableF :: *;
import NapWrapper :: *;

typedef 3 RINGBUF_NUMBER_WIDTH;

typedef 32   USER_LOGIC_DESCRIPTOR_BYTE_WIDTH;
typedef TMul#(USER_LOGIC_DESCRIPTOR_BYTE_WIDTH, BYTE_WIDTH)  USER_LOGIC_DESCRIPTOR_BIT_WIDTH; // 256 bit

typedef Bit#(USER_LOGIC_DESCRIPTOR_BIT_WIDTH)   RingbufRawDescriptor;
typedef Bit#(RINGBUF_NUMBER_WIDTH)              RingbufNumber;

function Bool isRingbufNotEmpty(RingbufPointer#(sz_rbp) head, RingbufPointer#(sz_rbp) tail);
    return !(head == tail);
endfunction

function Bool isRingbufNotFull(RingbufPointer#(sz_rbp) head, RingbufPointer#(sz_rbp) tail);
    return !((head.idx == tail.idx) && (head.guard != tail.guard));
endfunction


typedef struct {
    Bool guard;
    UInt#(w) idx;
} RingbufPointer#(numeric type w) deriving(Bits, Eq);

instance Arith#(RingbufPointer#(w)) provisos(Alias#(RingbufPointer#(w), data_t), Bits#(data_t, TAdd#(w, 1)));
    function data_t \+ (data_t x, data_t y);
        UInt#(TAdd#(w,1)) tx = unpack(pack(x));
        UInt#(TAdd#(w,1)) ty = unpack(pack(y));
        return unpack(pack(tx + ty));
    endfunction

    function data_t \- (data_t x, data_t y);
        UInt#(TAdd#(w,1)) tx = unpack(pack(x));
        UInt#(TAdd#(w,1)) ty = unpack(pack(y));
        return unpack(pack(tx - ty));
    endfunction

    function data_t \* (data_t x, data_t y);
        return error ("The operator " + quote("*") +
                      " is not defined for " + quote("RingbufPointer") + ".");
    endfunction

    function data_t \/ (data_t x, data_t y);
        return error ("The operator " + quote("/") +
                      " is not defined for " + quote("RingbufPointer") + ".");
    endfunction

    function data_t \% (data_t x, data_t y);
        return error ("The operator " + quote("%") +
                      " is not defined for " + quote("RingbufPointer") + ".");
    endfunction

    function data_t negate (data_t x);
        return error ("The operator " + quote("negate") +
                      " is not defined for " + quote("RingbufPointer") + ".");
    endfunction

endinstance

instance Literal#(RingbufPointer#(w));

   function fromInteger(n) ;
        return unpack(fromInteger(n)) ;
   endfunction
   function inLiteralRange(a, i);
        UInt#(w) idxPart = ?;
        return inLiteralRange(idxPart, i);
   endfunction
endinstance


typedef 4096  USER_LOGIC_RING_BUF_4096_DEEP; 
typedef TLog#(USER_LOGIC_RING_BUF_4096_DEEP)  USER_LOGIC_RING_BUF_4096_DEEP_WIDTH; 
typedef RingbufPointer#(USER_LOGIC_RING_BUF_4096_DEEP_WIDTH) Fix128kBRingBufPointer;
typedef RingbufC2h#(USER_LOGIC_RING_BUF_4096_DEEP_WIDTH) RingbufC2hSlot4096;

typedef 8 RINGBUF_DESC_ENTRY_PER_READ_BLOCK;
typedef 4 RINGBUF_DESC_ENTRY_PER_WRITE_BLOCK;


typedef Bit#(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)) RingBufReadBlockOffset;
typedef Bit#(TLog#(RINGBUF_DESC_ENTRY_PER_WRITE_BLOCK)) RingBufWriteBlockOffset;

typedef struct {
    ADDR addr;
    RingBufReadBlockOffset zeroBasedDescReadCnt;
} RingbufDmaReadReq deriving(Bits, FShow);

typedef struct {
    DataStream data;
} RingbufDmaReadResp deriving(Bits, FShow);

typedef struct {
    ADDR addr;
    RingBufWriteBlockOffset zeroBasedDescWriteCnt;
} RingbufDmaWriteReq deriving(Bits, FShow);

typedef struct {
    Bool isSuccess;
} RingbufDmaWriteResp deriving(Bits, FShow);


interface RingbufH2cMetadata;
    interface Reg#(ADDR) addr;
    interface Reg#(Fix128kBRingBufPointer) head;
    interface Reg#(Fix128kBRingBufPointer) tail;
endinterface

interface RingbufH2c;
    interface RingbufH2cMetadata controlRegs;
    interface PipeOut#(RingbufDmaReadReq) dmaReadReqPipeOut;
    interface PipeIn#(RingbufDmaReadResp) dmaReadRespPipeIn;
    interface PipeOut#(RingbufRawDescriptor) descPipeOut;
endinterface


// Important Note: The whole algorithm below based on the fact that the NAP bit width is 256 bits, and
// is the same as our descriptor size, so when doing aligned memory read, each NAP read beat is a 
// complete descriptor.
module mkRingbufH2c(RingbufNumber qIdx, Integer internalBufSize, RingbufH2c ifc) provisos (
        Alias#(tReadBlockIndex, Bit#(TSub#(SizeOf#(Fix128kBRingBufPointer), TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK))))
    );

    FIFOF#(RingbufRawDescriptor) bufQ <- mkSizedFIFOF(internalBufSize);
    FIFOF#(RingbufRawDescriptor) outputQ <- mkFIFOF;

    mkConnection(toGet(bufQ), toPut(outputQ));
    
    Reg#(ADDR) baseAddrReg <- mkReg(0);
    Reg#(Fix128kBRingBufPointer) headReg[2] <- mkCReg(2, unpack(0));
    Reg#(Fix128kBRingBufPointer) tailReg[2] <- mkCReg(2, unpack(0));
    Reg#(Fix128kBRingBufPointer) tailShadowReg <- mkConfigReg(unpack(0));
    FIFOF#(RingbufDmaReadReq) dmaReqQ <- mkFIFOF;
    FIFOF#(RingbufDmaReadResp) dmaRespQ <- mkFIFOF;

    Reg#(Bool) isWaitingDmaRespReg <- mkReg(False);
    
    rule sendDmaReq if (isWaitingDmaRespReg == False);

        tReadBlockIndex readBlockIdxOfHead = truncate(pack(headReg[0]) >> valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)));
        tReadBlockIndex readBlockIdxOfTailShadow = truncate(pack(tailShadowReg) >> valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)));

        Bool isHeadAndTailShadowInTheSameReadBlock = readBlockIdxOfHead == readBlockIdxOfTailShadow;
        Bool needDoDMA = isRingbufNotEmpty(headReg[0], tailShadowReg) && !bufQ.notEmpty;

        RingBufReadBlockOffset tailShadowRingBufReadBlockOffset = truncate(pack(tailShadowReg));
        let zeroBasedMaxDescReadCnt = fromInteger(valueOf(RINGBUF_DESC_ENTRY_PER_READ_BLOCK) - 1) - tailShadowRingBufReadBlockOffset;
        RingBufReadBlockOffset spanBetweenHeadAndTailShadow = truncate(pack(headReg[0])) - truncate(pack(tailShadowReg));

        Fix128kBRingBufPointer nextReadBlockAlignedPointer = unpack(pack(tailShadowReg) >> valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)));
        nextReadBlockAlignedPointer = nextReadBlockAlignedPointer + 1;
        nextReadBlockAlignedPointer = unpack(pack(nextReadBlockAlignedPointer) << valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)));
        
        ADDR dmaReadStartAddr = baseAddrReg + (zeroExtend(pack(tailShadowReg.idx)) << valueOf(DATA_BUS_BYTE_NUM_WIDTH));

        if (needDoDMA) begin

            RingBufReadBlockOffset zeroBasedDescReadCnt = ?;
            Fix128kBRingBufPointer newTailShadow = ?;
            if (isHeadAndTailShadowInTheSameReadBlock) begin
                zeroBasedDescReadCnt = spanBetweenHeadAndTailShadow - 1;
                newTailShadow = headReg[0];
            end
            else begin
                zeroBasedDescReadCnt = zeroBasedMaxDescReadCnt;
                newTailShadow = nextReadBlockAlignedPointer;
            end
            
            dmaReqQ.enq(RingbufDmaReadReq{
                    addr: dmaReadStartAddr,
                    zeroBasedDescReadCnt: zeroBasedDescReadCnt
            });

            tailShadowReg <= newTailShadow;
            isWaitingDmaRespReg <= True;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRingbufH2c sendDmaReq"),
            //     toBlue(", qIdx="), fshow(qIdx),
            //     toBlue(", headReg="), fshow(pack(headReg[0])),
            //     toBlue(", old tailReg="), fshow(pack(tailReg[0])),
            //     toBlue(", tailShadowReg="), fshow(pack(tailShadowReg)),
            //     toBlue(", zeroBasedDescReadCnt="), fshow(pack(zeroBasedDescReadCnt)),
            //     toBlue(", head-tail="), fshow(pack(headReg[0]-tailReg[0])),
            //     toBlue(", head-tailS="), fshow(pack(headReg[0]-tailShadowReg))
            // );
        end

        
    endrule


    rule recvDmaResp if (isWaitingDmaRespReg == True);
        let readRespDs = dmaRespQ.first;
        dmaRespQ.deq;

        bufQ.enq(unpack(readRespDs.data.data));
        let newTail = tailReg[0] + 1;
        tailReg[0] <= newTail;

        if (readRespDs.data.isLast) begin
            // $display("current read block finished.");
            isWaitingDmaRespReg <= False;
            immAssert(
                newTail == tailShadowReg,
                "shadowTail assertion @ mkRingbufH2cMetadata",
                $format(
                    "newTail=%h should == shadowTail=%h, ",
                    newTail, tailShadowReg
                )
            );
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRingbufH2c recvDmaResp"),
        //     toBlue(", qIdx="), fshow(qIdx),
        //     toBlue(", headReg="), fshow(pack(headReg[0])),
        //     toBlue(", old tailReg="), fshow(pack(tailReg[0])),
        //     toBlue(", new tailReg="), fshow(pack(newTail)),
        //     toBlue(", tailShadowReg="), fshow(pack(tailShadowReg)),
        //     toBlue(", desc="), fshow(readRespDs)
        // );
    endrule

    interface RingbufH2cMetadata controlRegs;
        interface addr = baseAddrReg;
        interface head = headReg[1];
        interface tail = tailReg[1];
    endinterface

    interface dmaReadReqPipeOut = toPipeOut(dmaReqQ);
    interface dmaReadRespPipeIn = toPipeIn(dmaRespQ);

    interface descPipeOut = toPipeOut(outputQ);
endmodule



interface RingbufC2hMetadata#(numeric type szPtrIdx);
    interface Reg#(ADDR) addr;
    interface Reg#(RingbufPointer#(szPtrIdx)) head;
    interface Reg#(RingbufPointer#(szPtrIdx)) tail;
endinterface

interface RingbufC2h#(numeric type szPtrIdx);
    interface RingbufC2hMetadata#(szPtrIdx) controlRegs;
    interface PipeOut#(RingbufDmaWriteReq) dmaWriteReqPipeOut;
    interface PipeOut#(DataStream) dmaWriteDataPipeOut;
    interface PipeIn#(Bool) dmaWriteRespPipeIn;
    interface PipeIn#(RingbufRawDescriptor) descPipeIn;
endinterface


// TODO: For C2H, doesn't support batch descriptor writeback now. 
module mkRingbufC2h(RingbufNumber qIdx, RingbufC2h#(szPtrIdx) ifc) provisos(
        NumAlias#(TAdd#(1, szPtrIdx), szPtrWithGuard),
        Alias#(Bit#(TSub#(szPtrWithGuard, TLog#(RINGBUF_DESC_ENTRY_PER_WRITE_BLOCK))), tWriteBlockIndex),
        Alias#(RingbufPointer#(szPtrIdx), tPtrWithGuard),
        Add#(a__, 2, TAdd#(1, szPtrIdx)),
        Add#(b__, 4, TAdd#(1, szPtrIdx)),
        Add#(c__, szPtrIdx, SizeOf#(ADDR))
    );

    Count#(Bit#(TAdd#(1, TLog#(NUMERIC_TYPE_EIGHT)))) validCounter <- mkCount(0);
    FIFOF#(RingbufRawDescriptor) bufQ <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_EIGHT));
    FIFOF#(RingbufRawDescriptor)                            inputQ  <- mkFIFOF;

    rule forwardInput;
        inputQ.deq;
        bufQ.enq(inputQ.first);
        validCounter.incr(1);
    endrule

    Reg#(ADDR)                      baseAddrReg     <- mkReg(0);
    Reg#(tPtrWithGuard)    headReg[2]      <- mkCReg(2, unpack(0));
    Reg#(tPtrWithGuard)    tailReg[2]      <- mkCReg(2, unpack(0));
    Reg#(tPtrWithGuard)    headShadowReg   <- mkConfigReg(unpack(0));
    FIFOF#(RingbufDmaWriteReq)      dmaWriteAddrQ   <- mkFIFOF;
    FIFOF#(DataStream)              dmaWriteDataQ   <- mkFIFOF;
    FIFOF#(Bool)                    dmaWriteRespQ   <- mkFIFOF;
    FIFOF#(tPtrWithGuard)           inFlightWriteReqHeaadUpdateQ <- mkFIFOF;

    Reg#(Bit#(NUMERIC_TYPE_TWO))       batchDelayCounterReg        <- mkReg(0);
    Reg#(Bool)                          isSendingDescBodyReg        <- mkReg(False);
    Reg#(RingBufWriteBlockOffset)       zeroBasedDescWriteCntReg    <- mkRegU;
    

    rule handleBatchDelay;
        if (!bufQ.notEmpty) begin
            batchDelayCounterReg <= 0;
        end
        else begin
            if (batchDelayCounterReg != -1) begin
                batchDelayCounterReg <= batchDelayCounterReg + 1;
            end
        end
    endrule
    
    rule prepareDmaWrite if (!isSendingDescBodyReg);

        Bool isBatchDelayCounterFired = batchDelayCounterReg == -1;
        tPtrWithGuard freeSlotCnt = fromInteger(valueOf(TExp#(szPtrIdx))) - (headShadowReg - tailReg[0]);
        tPtrWithGuard zeroBasedFreeSlotCnt = fromInteger(valueOf(TExp#(szPtrIdx)) - 1) - (headShadowReg - tailReg[0]);
        tPtrWithGuard zeroBasedAvailableDescToWrite = unpack(zeroExtend(pack(validCounter-1)));
        RingBufWriteBlockOffset headShadowRingBufWriteBlockOffset = truncate(pack(headShadowReg));
        tPtrWithGuard zeroBasedMaxDescWriteCntIfAlignedToWriteBlock = fromInteger(valueOf(RINGBUF_DESC_ENTRY_PER_WRITE_BLOCK) - 1) - unpack(zeroExtend(headShadowRingBufWriteBlockOffset));

        RingBufWriteBlockOffset zeroBasedDescWriteCnt = truncate(min(min(pack(zeroBasedMaxDescWriteCntIfAlignedToWriteBlock), pack(zeroBasedAvailableDescToWrite)), pack(zeroBasedFreeSlotCnt)));

        Bool needDoDMA = isBatchDelayCounterFired && bufQ.notEmpty && (pack(freeSlotCnt) > 0);
        if (needDoDMA) begin
            ADDR dmaWriteStartAddr = baseAddrReg + (zeroExtend(pack(headShadowReg.idx)) << valueOf(DATA_BUS_BYTE_NUM_WIDTH));
            dmaWriteAddrQ.enq(RingbufDmaWriteReq{
                addr: dmaWriteStartAddr,
                zeroBasedDescWriteCnt: zeroBasedDescWriteCnt
            });
            zeroBasedDescWriteCntReg <= zeroBasedDescWriteCnt;
            isSendingDescBodyReg <= True;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRingbufC2h prepareDmaWrite"),
            //     "needDoDMA=", fshow(needDoDMA),
            //     ", isBatchDelayCounterFired=",fshow(isBatchDelayCounterFired),
            //     ", bufQ.notEmpty=", fshow(bufQ.notEmpty),
            //     ", freeSlotCnt=", fshow(pack(freeSlotCnt)),
            //     ", zeroBasedDescWriteCnt=", fshow(pack(zeroBasedDescWriteCnt)),
            //     ", headReg=", fshow(pack(headReg[0])),
            //     ", headShadowReg=", fshow(pack(headShadowReg)),
            //     ", tailReg=", fshow(pack(tailReg[0])),
            //     ", head-tail=", fshow(pack(headReg[0] - tailReg[0])),
            //     ", headS-tail=", fshow(pack(headShadowReg - tailReg[0])),
            //     ", validCounter=", fshow(pack(validCounter)),
            //     ", zeroBasedAvailableDescToWrite=", fshow(pack(zeroBasedAvailableDescToWrite))
            // );
        end

    endrule

    rule doDmaWrite if (isSendingDescBodyReg);
        Bool isLast = False;

        let newHeadShadow = headShadowReg + 1;

        
        if (isZeroR(zeroBasedDescWriteCntReg)) begin
            isSendingDescBodyReg <= False;
            isLast = True;
            inFlightWriteReqHeaadUpdateQ.enq(newHeadShadow);
        end

        DataStream ds;
        ds.isLast = isLast; 
        ds.isFirst = ?;       // since AXI interface don't care isFirst Flag.
        ds.byteNum = fromInteger(valueOf(USER_LOGIC_DESCRIPTOR_BYTE_WIDTH));
        ds.data = unpack(pack(bufQ.first));
        ds.startByteIdx = 0;
        bufQ.deq;
        validCounter.decr(1);

        dmaWriteDataQ.enq(ds);
        
        zeroBasedDescWriteCntReg <= zeroBasedDescWriteCntReg - 1;
        headShadowReg <= newHeadShadow;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRingbufC2h doDmaWrite"),
        //     toBlue(", qIdx="), fshow(qIdx),
        //     toBlue(", tailReg="), fshow(pack(tailReg[0])),
        //     toBlue(", headReg="), fshow(pack(headReg[0])),
        //     toBlue(", old headShadowReg="), fshow(pack(headShadowReg)),
        //     toBlue(", new headShadowReg="), fshow(pack(newHeadShadow)),
        //     toBlue(", desc="), fshow(ds)
        // );
    endrule

    rule handleWriteResp;
        dmaWriteRespQ.deq;
        let newHead = inFlightWriteReqHeaadUpdateQ.first;
        inFlightWriteReqHeaadUpdateQ.deq;

        headReg[0] <= newHead;
        
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRingbufC2h handleWriteResp"),
        //     toBlue(", qIdx="), fshow(qIdx),
        //     toBlue(", headReg="), fshow(pack(headReg[0])),
        //     toBlue(", newHead="), fshow(pack(newHead))
        // );
    endrule


    interface RingbufC2hMetadata controlRegs;
        interface addr = baseAddrReg;
        interface head = headReg[1];
        interface tail = tailReg[1];
    endinterface

    interface dmaWriteReqPipeOut    = toPipeOut(dmaWriteAddrQ);
    interface dmaWriteDataPipeOut   = toPipeOut(dmaWriteDataQ);
    interface dmaWriteRespPipeIn    = toPipeIn(dmaWriteRespQ);

    interface descPipeIn = toPipeIn(inputQ);
endmodule

interface RingbufDmaNapWrappr;
    interface PipeIn#(RingbufDmaReadReq) dmaReadReqPipeIn;
    interface PipeOut#(RingbufDmaReadResp) dmaReadRespPipeOut;
    interface PipeOut#(Bool) dmaWriteRespPipeOut;
    interface PipeIn#(RingbufDmaWriteReq) dmaWriteReqPipeIn;
    interface PipeIn#(DataStream) dmaWriteDataPipeIn;
endinterface

module mkRingbufDmaNapWrappr(RingbufDmaNapWrappr);
    FIFOF#(RingbufDmaReadReq)   dmaReadReqPipeInQ       <- mkFIFOF;
    FIFOF#(RingbufDmaReadResp)  dmaReadRespPipeOutQ     <- mkFIFOF;
    FIFOF#(RingbufDmaWriteReq)  dmaWriteReqPipeInQ      <- mkFIFOF;
    FIFOF#(DataStream)          dmaWriteDataPipeInQ     <- mkFIFOF;
    FIFOF#(Bool)                dmaWriteRespPipeOutQ    <- mkFIFOF;

    AcxNapSlaveWrapperPipe nap <- mkAcxNapSlaveWrapperPipe;

    rule forwardWriteAddr;
        let req = dmaWriteReqPipeInQ.first;
        dmaWriteReqPipeInQ.deq;

        let aw = AxiMmNapBeatAw {
            awid: 0,
            awaddr: truncate(req.addr),
            awlen: unpack(zeroExtend(req.zeroBasedDescWriteCnt)),
            awsize: unpack(pack(NapAxiSize32B)),
            awburst: unpack(pack(NapAxiBurstIncr)),
            awlock: False,
            awqos: 0
        };
        nap.writePipeIfc.writeAddrPipeIn.enq(aw);
    endrule

    rule forwardWriteData;
        let req = dmaWriteDataPipeInQ.first;
        dmaWriteDataPipeInQ.deq;

        let w = AxiMmNapBeatW {
            wdata: unpack(pack(req.data)),
            wstrb: -1,
            wlast: req.isLast
        };
        nap.writePipeIfc.writeDataPipeIn.enq(w);
    endrule

    rule forwardWriteResp;
        let resp = nap.writePipeIfc.writeRespPipeOut.first;
        nap.writePipeIfc.writeRespPipeOut.deq;
        dmaWriteRespPipeOutQ.enq(resp.bresp == 0);
    endrule

    rule forwardReadReq;
        let req = dmaReadReqPipeInQ.first;
        dmaReadReqPipeInQ.deq;

        let ar = AxiMmNapBeatAr {
            arid: 0,
            araddr: truncate(req.addr),
            arlen: unpack(zeroExtend(req.zeroBasedDescReadCnt)),
            arsize: unpack(pack(NapAxiSize32B)),
            arburst: unpack(pack(NapAxiBurstIncr)),
            arlock: False,
            arqos: 0
        };
        nap.readPipeIfc.readAddrPipeIn.enq(ar);
    endrule

    rule forwardReadResp;
        let resp = nap.readPipeIfc.readRespPipeOut.first;
        nap.readPipeIfc.readRespPipeOut.deq;

        let ds = RingbufDmaReadResp {
            data: DataStream {
                data: resp.rdata,
                byteNum: fromInteger(valueOf(USER_LOGIC_DESCRIPTOR_BYTE_WIDTH)),
                startByteIdx: 0,
                isFirst: dontCareValue,
                isLast: resp.rlast
            }
        };

        dmaReadRespPipeOutQ.enq(ds);
    endrule

    interface dmaReadReqPipeIn = toPipeIn(dmaReadReqPipeInQ);
    interface dmaReadRespPipeOut = toPipeOut(dmaReadRespPipeOutQ);
    interface dmaWriteReqPipeIn = toPipeIn(dmaWriteReqPipeInQ);
    interface dmaWriteDataPipeIn = toPipeIn(dmaWriteDataPipeInQ);
    interface dmaWriteRespPipeOut = toPipeOut(dmaWriteRespPipeOutQ);
endmodule