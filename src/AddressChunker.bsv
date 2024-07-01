import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;

typedef 16 AXI_MAX_BURST_BEATS;
typedef TMul#(AXI_MAX_BURST_BEATS, DATA_BUS_BYTE_WIDTH) AXI_MAX_BURST_BYTES;                        // 512

typedef TSub#(4096, 1) AXI_ADDR_4K_BOUNDARY_MASK;                                                   // 'hFFF
typedef TSub#(DATA_BUS_BYTE_WIDTH, 1) AXI_ADDR_32B_BOUNDARY_MASK;                                   // 'h1F  
typedef TSub#(AXI_MAX_BURST_BYTES, 1) AXI_ADDR_512B_BOUNDARY_MASK;                                  // 'h1FF           Achronix NAP is (256 bits * 16 bursts) max, which is 512 Bytes

typedef TLog#(AXI_MAX_BURST_BYTES) AXI_BURST_BYTE_NUM_WIDTH;                                        // 9
typedef Bit#(AXI_BURST_BYTE_NUM_WIDTH) ByteIdxInAxiBurst;
typedef Bit#(TAdd#(1, AXI_BURST_BYTE_NUM_WIDTH)) ByteNumInAxiBurst;  

typedef TLog#(AXI_MAX_BURST_BEATS) BEAT_IDX_IN_AXI_BURST_WIDTH;                                     // 4
typedef Bit#(BEAT_IDX_IN_AXI_BURST_WIDTH) BeatIdxInAxiBurst;
typedef Bit#(TAdd#(1,BEAT_IDX_IN_AXI_BURST_WIDTH)) BeatNumInAxiBurst;

typedef TSub#(TSub#(RDMA_MAX_LEN_WIDTH, AXI_BURST_BYTE_NUM_WIDTH), BEAT_IDX_IN_AXI_BURST_WIDTH) BURST_IDX_IN_RDMA_LENGTH;         // 19
typedef Bit#(BURST_IDX_IN_RDMA_LENGTH) BurstIdxInRdmaLength;
typedef Bit#(TAdd#(1,BURST_IDX_IN_RDMA_LENGTH)) BurstNumInRdmaLength;

typedef struct {
    tAddr startAddr;
    tLen len;
    tChunk chunk;
} AddressChunkReq#(type tAddr, type tLen, type tChunk) deriving(Bits, FShow);

typedef struct {
    tAddr       startAddr;
    tLen        len;
    Bool        isFirst;
    Bool        isLast;
} AddressChunkResp#(type tAddr, type tLen) deriving(Bits, FShow);

typedef struct {
    tLen        zeroBasedChunkNum;
} AddressChunkRespMeta#(type tLen) deriving(Bits, FShow);

interface AddressTrunker#(type tAddr, type tLen, type tChunk, numeric type tMaxChunkSizeWidth);
    interface PipeIn#(AddressChunkReq#(tAddr, tLen, tChunk)) requestPipeIn;
    interface PipeOut#(AddressChunkResp#(tAddr, tLen)) responsePipeOut;
    interface PipeOut#(AddressChunkRespMeta#(tLen)) metaPipeOut;
endinterface



module mkAddressTrunker#(
        function Tuple2#(tAddr, tAddr) alignAddrByChunk(tAddr addr, tChunk chunk),
        function Tuple2#(tLen, tLen) divideLenByChunk(tLen len, tChunk chunk),
        function Bool isAddrAndLengthLowerPartSumOverflow(tLen len, tChunk chunk),
        function tLen getChunkSize(tChunk chunk)
    )(AddressTrunker#(tAddr, tLen, tChunk, tMaxChunkSizeWidth)) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tLen, szLen),
        Bits#(tChunk, szChunk),
        Bitwise#(tAddr),
        Bitwise#(tLen),
        Arith#(tLen),
        Add#(b__, szLen, szAddr),
        Ord#(tLen),
        Arith#(tAddr), 
        Alias#(Bit#(TAdd#(1, tMaxChunkSizeWidth)), tInternalMathOp),
        Bits#(tInternalMathOp, szInternalMathOp),
        Add#(a__, szInternalMathOp, szAddr),
        Add#(c__, szInternalMathOp, szLen),
        FShow#(AddressChunker::AddressChunkReq#(tAddr, tLen, tChunk))
    );

    FIFOF#(AddressChunkReq#(tAddr, tLen, tChunk)) reqQ <- mkFIFOF;
    FIFOF#(AddressChunkResp#(tAddr, tLen)) respQ <- mkFIFOF;
    FIFOF#(AddressChunkRespMeta#(tLen)) respMetaQ <- mkFIFOF;

    // Pipeline FIFOs
    FIFOF#(Tuple7#(AddressChunkReq#(tAddr, tLen, tChunk), tLen, Bool, Bool, tInternalMathOp, tInternalMathOp, tAddr)) preCalcPipelineQ <- mkFIFOF;


    Reg#(Bool) busyReg <- mkReg(False);
    
    Reg#(tLen) remainingChunkNumReg <- mkRegU;
    Reg#(tAddr) nextAddrReg <- mkRegU;
    Reg#(tLen) remainingLenReg <- mkRegU;
    Reg#(tInternalMathOp) chunkSizeReg <- mkRegU;

    rule preCalculate;

        let req = reqQ.first;
        reqQ.deq;

        let {devidedLen, lenRemainderTmp} = divideLenByChunk(req.len, req.chunk);
        let {alignedAddr, addrRemainderTmp} = alignAddrByChunk(req.startAddr, req.chunk);
        tInternalMathOp chunkSize = unpack(truncate(pack(getChunkSize(req.chunk))));

        tInternalMathOp lenRemainder = unpack(truncate(pack(lenRemainderTmp)));
        tInternalMathOp addrRemainder = unpack(truncate(pack(addrRemainderTmp)));
        
        let zeroBasedChunkNum = devidedLen;
        
        tInternalMathOp tmpSumResult = lenRemainder + addrRemainder;

        let needAnotherBurst = isAddrAndLengthLowerPartSumOverflow(unpack(zeroExtend(pack(tmpSumResult))), req.chunk);

        Bool isOnlyChunk = isZeroR(pack(zeroBasedChunkNum)) && !needAnotherBurst;



        
        let nextAddr = alignedAddr + unpack(zeroExtend(pack(chunkSize)));  // should we extract it to a function to reduce add bits?

        let pipeLineEntry = tuple7(req, zeroBasedChunkNum, needAnotherBurst, isOnlyChunk, chunkSize, addrRemainder, nextAddr);
        preCalcPipelineQ.enq(pipeLineEntry);
        

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressTrunker preCalculate"),
        //     toBlue(", req="), fshow(req),
        //     toBlue(", remainingChunkNum="), fshow(remainingChunkNum),
        //     toBlue(", isOnlyChunk="), fshow(isOnlyChunk),
        //     toBlue(", chunkSize="), fshow(chunkSize),
        //     toBlue(", addrRemainder="), fshow(addrRemainder),
        //     toBlue(", nextAddr="), fshow(nextAddr),
        //     toBlue(", outMeta="), fshow(outMeta)
        // );
    endrule

    rule doFirstBeat if (!busyReg);

        let {req, zeroBasedChunkNum, needAnotherBurst, isOnlyChunk, chunkSize, addrRemainder, nextAddr} = preCalcPipelineQ.first;
        preCalcPipelineQ.deq;

        
        chunkSizeReg <= chunkSize;
        nextAddrReg <= nextAddr;
        busyReg <= !isOnlyChunk;
        remainingLenReg <= req.len - unpack(zeroExtend((chunkSize - truncate(pack(addrRemainder)))));

        let isFirst = True;
        let isLast = isOnlyChunk;





        if (needAnotherBurst) begin
            zeroBasedChunkNum = zeroBasedChunkNum + 1;
        end

        let outMeta = AddressChunkRespMeta{
            zeroBasedChunkNum: zeroBasedChunkNum
        };

        let remainingChunkNum = zeroBasedChunkNum;

        remainingChunkNumReg <= remainingChunkNum;







        tAddr startAddr = req.startAddr;
        tLen len = isOnlyChunk ? req.len : unpack(zeroExtend(pack(chunkSize - addrRemainder)));

        let outEntry = AddressChunkResp {
            startAddr: startAddr,
            len: len, 
            isFirst: True,
            isLast: isLast
        };

        respMetaQ.enq(outMeta);
        respQ.enq(outEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressTrunker doFirstBeat"),
        //     toBlue(", req="), fshow(req),
        //     toBlue(", remainingChunkNum="), fshow(remainingChunkNum),
        //     toBlue(", isOnlyChunk="), fshow(isOnlyChunk),
        //     toBlue(", chunkSize="), fshow(chunkSize),
        //     toBlue(", addrRemainder="), fshow(addrRemainder),
        //     toBlue(", nextAddr="), fshow(nextAddr),
        //     toBlue(", startAddr="), fshow(startAddr),
        //     toBlue(", len="), fshow(len),
        //     toBlue(", outEntry="), fshow(outEntry)
        // );

    endrule

    rule doOtherBeat if (busyReg);
        let isLast = isOneR(pack(remainingChunkNumReg));
        if (isLast) begin
            busyReg <= False;
        end
        else begin
            remainingChunkNumReg <= remainingChunkNumReg - 1;
        end

        let newNextAddr = nextAddrReg + unpack(zeroExtend(pack(chunkSizeReg)));
        nextAddrReg <= newNextAddr;
        let newRemainingLen = remainingLenReg - unpack(zeroExtend(chunkSizeReg));
        remainingLenReg <= newRemainingLen;

        let outEntry = AddressChunkResp {
            startAddr: nextAddrReg,
            len: isLast ? remainingLenReg : unpack(zeroExtend(pack(chunkSizeReg))), 
            isFirst: False,
            isLast: isLast
        };
        respQ.enq(outEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressTrunker doOtherBeat"),
        //     toBlue(", remainingChunkNumReg="), fshow(remainingChunkNumReg),
        //     toBlue(", nextAddrReg="), fshow(nextAddrReg),
        //     toBlue(", newNextAddr="), fshow(newNextAddr),
        //     toBlue(", remainingLenReg="), fshow(remainingLenReg),
        //     toBlue(", newRemainingLen="), fshow(newRemainingLen),
        //     toBlue(", outEntry="), fshow(outEntry)
        // );
    endrule
    
    interface requestPipeIn = toPipeIn(reqQ);
    interface responsePipeOut = toPipeOut(respQ);
    interface metaPipeOut = toPipeOut(respMetaQ);
endmodule


function Tuple2#(ADDR, ADDR) alignAddrByPMTU(ADDR addr, PMTU pmtu);
    return case (pmtu)
        IBV_MTU_256 : begin
            // 8 = log2(256)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 8], 8'b0 }, zeroExtend(addr[7 : 0]));
        end
        IBV_MTU_512 : begin
            // 9 = log2(512)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 9], 9'b0 }, zeroExtend(addr[8 : 0]));
        end
        IBV_MTU_1024: begin
            // 10 = log2(1024)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 10], 10'b0 }, zeroExtend(addr[9 : 0]));
        end
        IBV_MTU_2048: begin
            // 11 = log2(2048)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 11], 11'b0 }, zeroExtend(addr[10 : 0]));
        end
        IBV_MTU_4096: begin
            // 12 = log2(4096)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 12], 12'b0 }, zeroExtend(addr[11 : 0]));
        end
    endcase;
endfunction


function Tuple2#(Length, Length) devideLengthByPMTU(Length len, PMTU pmtu);
    return case (pmtu)
        IBV_MTU_256 : begin
            // 8 = log2(256)
            tuple2({ 8'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 8] }, zeroExtend(len[7 : 0]));
        end
        IBV_MTU_512 : begin
            // 9 = log2(512)
            tuple2({ 9'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 9] }, zeroExtend(len[8 : 0]));
        end
        IBV_MTU_1024: begin
            // 10 = log2(1024)
            tuple2({ 10'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 10] }, zeroExtend(len[9 : 0]));
        end
        IBV_MTU_2048: begin
            // 11 = log2(2048)
            tuple2({ 11'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 11] }, zeroExtend(len[10 : 0]));
        end
        IBV_MTU_4096: begin
            // 12 = log2(4096)
            tuple2({ 12'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 12] }, zeroExtend(len[11 : 0]));
        end
    endcase;
endfunction


function Bool isAddrAndLengthLowerPartSumOverflowPMTU(Length len, PMTU pmtu);
    return case (pmtu)
        IBV_MTU_256 : begin
            // 8 = log2(256)
            (len[8] == 1);
        end
        IBV_MTU_512 : begin
            // 9 = log2(512)
            (len[9] == 1);
        end
        IBV_MTU_1024: begin
            // 10 = log2(1024)
            (len[10] == 1);
        end
        IBV_MTU_2048: begin
            // 11 = log2(2048)
            (len[11] == 1);
        end
        IBV_MTU_4096: begin
            // 12 = log2(4096)
            (len[12] == 1);
        end
    endcase;
endfunction

function Length getChunkSizeForPMTU(PMTU pmtu);
    return case (pmtu)
        IBV_MTU_256 : begin
            // 8 = log2(256)
            256;
        end
        IBV_MTU_512 : begin
            // 9 = log2(512)
            512;
        end
        IBV_MTU_1024: begin
            // 10 = log2(1024)
            1024;
        end
        IBV_MTU_2048: begin
            // 11 = log2(2048)
            2048;
        end
        IBV_MTU_4096: begin
            // 12 = log2(4096)
            4096;
        end
    endcase;
endfunction

