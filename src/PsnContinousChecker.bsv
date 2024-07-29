import DataTypes :: *;
import RdmaHeaders :: *;

import ConnectableF :: *;

typedef 128 BITMAP_BIT_WIDTH_PER_BANK;
typedef Bit#(BITMAP_BIT_WIDTH_PER_BANK) BitmapPerBank;

typedef TLog#(BITMAP_BIT_WIDTH_PER_BANK) BITMAP_BIT_INDEX_WIDTH;
typedef Bit#(BITMAP_BIT_INDEX_WIDTH) BitmapBitIdx;

typedef 4 BITMAP_BANK_NUM;
typedef TLog#(BITMAP_BANK_NUM) BITMAP_BANK_IDNEX_WIDTH;
typedef Bit#(BITMAP_BANK_IDNEX_WIDTH) BitmapBankIdx;

typedef TSub#(PSN_WIDTH, TAdd#(BITMAP_BIT_INDEX_WIDTH, BITMAP_BANK_IDNEX_WIDTH)) BITMAP_BANK_TAG_BIT_WIDTH;
typedef Bit#(BITMAP_BANK_TAG_BIT_WIDTH) BitmapBankTag;

typedef 4 CPSN_CHECKER_CHANNEL_NUM;

typedef struct {
    PSN psn;
    QPN qpn;
    Bool needAck;
} PsnContinousCheckerReq deriving(Bits, FShow);

typedef struct {
    QPN qpn;
    PSN cpsn;
    Maybe#(BitmapPerBank) evictedBitmapMaybe;
} PsnContinousCheckerResp deriving(Bits, FShow);

typedef struct {
    BitmapBankTag   tag;
    BitmapBankIdx   bankIdx;
    BitmapBitIdx    bitIdx;
} PsnAsBitmapIndex deriving(Bits, FShow);

interface PsnContinousCheckerAndAckAutoGen;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVec;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(PsnContinousCheckerResp)) respPipeOutVec;
endinterface


(* synthesize *)
module mkPsnContinousCheckerAndAckAutoGen(PsnContinousCheckerAndAckAutoGen);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(PsnContinousCheckerResp)) respPipeOutVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(PsnContinousCheckerReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(PsnContinousCheckerResp)) respPipeOutQueueVec <- replicateM(mkFIFOF);







    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end
    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;
endmodule


interface OneHotBankBitmapGen;
    interface PipeIn(PSN) psnPipeIn;
    interface PipeOut#(BitmapPerBank) bitmapPipeOut;
endinterface

module mkOneHotBankBitmapGen(OneHotBankBitmapGen);
    FIFOF#(PSN) psnPipeInQ <- mkFIFOF;
    FIFOF#(BitmapPerBank) bitmapPipeOutQ <- mkFIFOF;

    rule doShift;
        let psn = psnPipeInQ.first;
        psnPipeInQ.deq;

        PsnAsBitmapIndex psnAsBitmapIndex = unpack(pack(psn));
        BitmapPerBank out = 1 << psnAsBitmapIndex.bitIdx;

        bitmapPipeOutQ.enq(out);
    endrule

    interface psnPipeIn = toPipeIn(psnPipeInQ);
    interface bitmapPipeOut = toPipeOut(bitmapPipeOutQ);
endmodule