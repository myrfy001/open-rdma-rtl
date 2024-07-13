import Vector :: *;
import UserLogicSettings :: *;
import UserLogicTypes :: *;
import DataTypes :: *;
import Headers :: *;
import FIFOF :: *;
import Arbitration :: *;
import PAClib :: *;
import PrimUtils :: *;
import ClientServer :: *;
import GetPut :: *;
import ConfigReg :: * ;
import Randomizable :: *;
import PrimUtils :: *;
import RdmaUtils :: *;


function Bool isRingbufNotEmpty(RingbufPointer#(sz_rbp) head, RingbufPointer#(sz_rbp) tail);
    return !(head == tail);
endfunction

function Bool isRingbufNotFull(RingbufPointer#(sz_rbp) head, RingbufPointer#(sz_rbp) tail);
    return !((head.idx == tail.idx) && (head.guard != tail.guard));
endfunction

function Tuple2#(PageNumber128k, PageOffset128k) getPageNumberAndOffset4k(ADDR addr);
    return unpack(pack(addr));
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
        return RingbufPointer{ guard: False, idx: fromInteger(n) } ;
   endfunction
   function inLiteralRange(a, i);
        UInt#(w) idxPart = ?;
        return inLiteralRange(idxPart, i);
   endfunction
endinstance

typedef RingbufPointer#(USER_LOGIC_RING_BUF_4096_DEEP_WIDTH) Fix128kBRingBufPointer;

typedef Bit#(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)) ReadBlockOffset;

typedef struct {
    ADDR addr;
    ReadBlockOffset zeroBasedDescReadCnt;
} RingbufDmaReadReq;

typedef struct {
    ADDR addr;
    ReadBlockOffset zeroBasedDescReadCnt;
} RingbufDmaReadResp;


interface RingbufH2cMetadata;
    interface Reg#(ADDR) addr;
    interface Reg#(Fix128kBRingBufPointer) head;
    interface Reg#(Fix128kBRingBufPointer) tail;
    interface Reg#(Fix128kBRingBufPointer) tailShadow;
endinterface

interface RingbufH2c;
    interface RingbufH2cMetadata controlRegs;
    interface RingbufDmaH2cClt dmaClt;
    interface PipeOut#(RingbufRawDescriptor) descPipeout;
endinterface

module mkRingbufH2c(RingbufNumber qIdx, Integer internalBufSize, RingbufH2c ifc) provisos (
        Alias#(Bit#(TSub#(SizeOf#(Fix128kBRingBufPointer), TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK))), ReadBlockIndex)
    );

    FIFOF#(RingbufRawDescriptor) bufQ <- mkSizedFIFOF(internalBufSize);
    FIFOF#(RingbufRawDescriptor) outputQ <- mkFIFOF;

    mkConnection(toGet(bufQ), toPut(outputQ));
    

    Reg#(ADDR) baseAddrReg <- mkReg(0);
    Reg#(Fix128kBRingBufPointer) headReg[2] <- mkCReg(2, unpack(0));
    Reg#(Fix128kBRingBufPointer) tailReg[2] <- mkCReg(2, unpack(0));
    Reg#(Fix128kBRingBufPointer) tailShadowReg <- mkConfigReg(unpack(0));
    FIFOF#(UserLogicDmaH2cReq) dmaReqQ <- mkFIFOF;
    FIFOF#(UserLogicDmaH2cResp) dmaRespQ <- mkFIFOF;

    Reg#(Bool) isWaitingDmaRespReg <- mkReg(False);
    
    rule sendDmaReq if (isWaitingDmaRespReg == False);



        ReadBlockIndex readBlockIdxOfHead = truncate(headReg >> valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)));
        ReadBlockIndex readBlockIdxOfTailShadow = truncate(tailShadowReg >> valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)));

        Bool isHeadAndTailShadowInTheSameReadBlock = readBlockIdxOfHead == readBlockIdxOfTailShadow;
        Bool needDoDMA = isRingbufNotEmpty(headReg[0], tailShadowReg) && !bufQ.notEmpty;

        ReadBlockOffset tailShadowReadBlockOffset = truncate(tailShadowReg);
        let zeroBasedMaxDescReadCnt = fromInteger(valueOf(RINGBUF_DESC_ENTRY_PER_READ_BLOCK) - 1) - tailShadowReadBlockOffset;
        ReadBlockOffset spanBetweenHeadAndTailShadow = truncate(headReg) - truncate(tailShadowReg);
        
        if (needDoDMA) begin
            let zeroBasedDescReadCnt = isHeadAndTailShadowInTheSameReadBlock ? spanBetweenHeadAndTailShadow - 1 : zeroBasedMaxDescReadCnt;

        end


        // generate a temp constant var as mask, use it to align pointer.
        Fix4kBRingBufPointer ringbufReadBlockInnerOffsetMask = 0;
        ringbufReadBlockInnerOffsetMask.idx = ~((1 << valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK))) - 1); 

        if (isRingbufNotEmpty(headReg[0], tailShadowReg) && !bufQ.notEmpty) begin
            
            let readBlockAlignedTailShadow = tailShadowReg + fromInteger(valueOf(RINGBUF_DESC_ENTRY_PER_READ_BLOCK));
            readBlockAlignedTailShadow.idx = readBlockAlignedTailShadow.idx & ringbufReadBlockInnerOffsetMask.idx;

            let availableEntryCnt = headReg[0] - tailShadowReg;
            let avaliableSlotInReadBlock = fromInteger(valueOf(RINGBUF_DESC_ENTRY_PER_READ_BLOCK)) - pack(tailShadowReg.idx)[valueOf(TLog#(RINGBUF_DESC_ENTRY_PER_READ_BLOCK))-1:0];
            
            Fix4kBRingBufPointer newTailShadow;
            if (pack(availableEntryCnt) > avaliableSlotInReadBlock) begin
                newTailShadow = readBlockAlignedTailShadow;
            end 
            else begin
                newTailShadow = headReg[0];
            end

            dmaReqQ.enq(UserLogicDmaH2cReq{
                    addr: curReadBlockStartAddr,
                    len: fromInteger(valueOf(RINGBUF_BLOCK_READ_LEN))
            });
            // $display("h2c ringbuf send new dma request");
            tailPosInReadBlockReg <= truncate(pack(tailReg[0]));

            tailShadowReg <= newTailShadow;
            isWaitingDmaRespReg <= True;
        end
    endrule


    rule recvDmaResp if (isWaitingDmaRespReg == True);
        let {desc, isLast} = splitedDescQ.first;
        splitedDescQ.deq;

        if (tailPosInReadBlockReg > 0) begin
            // skip already consumed descriptors in previous block read.
            tailPosInReadBlockReg <= tailPosInReadBlockReg - 1;
            // $display("skip already handled...tailPosInReadBlockReg=", tailPosInReadBlockReg);
        end 
        else begin
            let newTail = tailReg[0];
            if (tailReg[0] != tailShadowReg) begin
                // the end of read block may contain invalid descriptors, don't handle descriptors beyond tailShadowReg
                t_elem t = unpack(pack(desc));
                // $display("Ringbuf H2c enqueue descriptor, qIdx=", fshow(qIdx), fshow(t));
                fifoCntrl.fillBuf(t);
                newTail = tailReg[0] + 1;
                tailReg[0] <= newTail;
                // $display("tail incr...old tailReg=%h, new=%x", tailReg[0], newTail);
            end 
            else begin
                // $display("skip invalid...tailReg=%h", tailReg[0]);
            end

            if (isLast) begin
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
        end
    endrule

    interface RingbufH2cMetadata metadata;
        interface addr = baseAddrReg;
        interface head = headReg[1];
        interface tail = tailReg[1];
        interface tailShadow = tailShadowReg;
    endinterface
    interface dmaClt = toGPClient(dmaReqQ, dmaRespQ);
    interface descPipeout = toPipeOut(outputQ);
endmodule



interface RingbufC2hMetadata;
    interface Reg#(ADDR) addr;
    interface Reg#(Fix4kBRingBufPointer) head;
    interface Reg#(Fix4kBRingBufPointer) tail;
    interface Reg#(Fix4kBRingBufPointer) headShadow;
endinterface

interface RingbufC2hController;
    interface RingbufC2hMetadata metadata;
    interface RingbufDmaC2hClt dmaClt;
endinterface


// TODO: For C2H, doesn't support batch descriptor writeback now. 
module mkRingbufC2hController(RingbufNumber qIdx, PipeOut#(t_elem) fifoCntrl, RingbufC2hController ifc)
    provisos(
        Bits#(t_elem, sz_elem),
        Bits#(RingbufRawDescriptor, sz_elem)
    );

    Reg#(ADDR) baseAddrReg <- mkReg(0);
    Reg#(Fix4kBRingBufPointer) headReg[2] <- mkCReg(2, unpack(0));
    Reg#(Fix4kBRingBufPointer) tailReg[2] <- mkCReg(2, unpack(0));
    Reg#(Fix4kBRingBufPointer) headShadowReg <- mkConfigReg(unpack(0));
    FIFOF#(UserLogicDmaC2hReq) dmaReqQ <- mkFIFOF;
    FIFOF#(UserLogicDmaC2hResp) dmaRespQ <- mkFIFOF;


    Reg#(RingbufReadBlockInnerOffset) headPosInReadBlockReg <- mkReg(0);

    
    rule sendDmaReq;

        if (isRingbufNotFull(headShadowReg, tailReg[0]) && fifoCntrl.notEmpty) begin

            let {curWriteBlockStartAddrPgn, _} = getPageNumberAndOffset4k(baseAddrReg);

            PageOffset4k curWriteBlockStartAddrOff = zeroExtend(
                headShadowReg.idx
            ) << valueOf(TLog#(USER_LOGIC_DESCRIPTOR_BYTE_WIDTH));

            ADDR curWriteStartAddr = unpack({pack(curWriteBlockStartAddrPgn), pack(curWriteBlockStartAddrOff)});

            DataStream ds;
            ds.isLast = True;
            ds.isFirst = True;
            ds.byteNum = fromInteger(valueOf(USER_LOGIC_DESCRIPTOR_BYTE_WIDTH));
            ds.data = unpack(zeroExtend(pack(fifoCntrl.first)));
            fifoCntrl.deq;

            dmaReqQ.enq(UserLogicDmaC2hReq{
                    addr: curWriteStartAddr,
                    len: fromInteger(valueOf(USER_LOGIC_DESCRIPTOR_BYTE_WIDTH)),
                    dataStream: dataStream2DataStreamEnRightAlign(ds)
            });


            headShadowReg <= headShadowReg + 1;
        end
    endrule

    rule recvDmaResp;
        dmaRespQ.deq;
        let resp = dmaRespQ.first;
        // $display("recvDmaResp @ Q=%d -- head = %x, tail = %x, head_shadow = %x", qIdx, headReg[0], tailReg[0], headShadowReg);
        let newHead = headReg[0] + 1;
        headReg[0] <= newHead;
        // $display("head incr...old headReg=%h, new=%x", headReg[0], newHead);
    endrule

    interface RingbufC2hMetadata metadata;
        interface addr = baseAddrReg;
        interface head = headReg[1];
        interface tail = tailReg[1];
        interface headShadow = headShadowReg;
    endinterface
    interface dmaClt = toGPClient(dmaReqQ, dmaRespQ);
endmodule