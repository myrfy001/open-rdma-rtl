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
    tLen                                    zeroBasedChunkNum;
    AddressChunkReq#(tAddr, tLen, tChunk)   req;
    tLen                                    devidedLen;
    Bit#(TAdd#(1, tMaxChunkSizeWidth))      chunkSize;
    Bit#(TAdd#(1, tMaxChunkSizeWidth))      addrRemainder;
    tAddr                                   nextAddr;
    Bool                                    isOnlyChunk;
} AddressChunkMeta#(type tAddr, type tLen, type tChunk, numeric type tMaxChunkSizeWidth) deriving(Bits, FShow);

interface AddressChunker#(type tAddr, type tLen, type tChunk, numeric type tMaxChunkSizeWidth);
    interface PipeIn#(AddressChunkMeta#(tAddr, tLen, tChunk, tMaxChunkSizeWidth)) requestPipeIn;
    interface PipeOut#(AddressChunkResp#(tAddr, tLen)) responsePipeOut;
endinterface



module mkAddressChunker(AddressChunker#(tAddr, tLen, tChunk, tMaxChunkSizeWidth)) provisos (
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

    FIFOF#(AddressChunkMeta#(tAddr, tLen, tChunk, tMaxChunkSizeWidth)) reqQ <- mkFIFOF;
    FIFOF#(AddressChunkResp#(tAddr, tLen)) respQ <- mkFIFOF;

    Reg#(Bool) busyReg <- mkReg(False);
    
    Reg#(tLen) remainingChunkNumReg <- mkRegU;
    Reg#(tAddr) nextAddrReg <- mkRegU;
    Reg#(tLen) remainingLenReg <- mkRegU;
    Reg#(tInternalMathOp) chunkSizeReg <- mkRegU;

    rule doFirstBeat if (!busyReg);


        let chunkMeta = reqQ.first;
        reqQ.deq;

        chunkSizeReg <= chunkMeta.chunkSize;
        nextAddrReg <= chunkMeta.nextAddr;
        busyReg <= !chunkMeta.isOnlyChunk;
        remainingLenReg <= chunkMeta.req.len - unpack(zeroExtend((chunkMeta.chunkSize - chunkMeta.addrRemainder)));

        let isFirst = True;
        let isLast = chunkMeta.isOnlyChunk;


        let remainingChunkNum = chunkMeta.zeroBasedChunkNum;

        remainingChunkNumReg <= remainingChunkNum;

        tAddr startAddr = chunkMeta.req.startAddr;
        tLen len = chunkMeta.isOnlyChunk ? chunkMeta.req.len : unpack(zeroExtend(pack(chunkMeta.chunkSize - chunkMeta.addrRemainder)));

        let outEntry = AddressChunkResp {
            startAddr: startAddr,
            len: len, 
            isFirst: True,
            isLast: isLast
        };

        respQ.enq(outEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressChunker doFirstBeat"),
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
        //     "time=%0t:", $time, toGreen(" mkAddressChunker doOtherBeat"),
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
endmodule



interface AddressChunkMetaCalculator#(type tAddr, type tLen, type tChunk, numeric type tMaxChunkSizeWidth);
    interface PipeIn#(AddressChunkReq#(tAddr, tLen, tChunk)) requestPipeIn;
    interface PipeOut#(AddressChunkMeta#(tAddr, tLen, tChunk, tMaxChunkSizeWidth)) metaPipeOut;
endinterface


module mkAddressChunkMetaCalculator#(
        function Tuple2#(tAddr, tAddr) alignAddrByChunk(tAddr addr, tChunk chunk),
        function Tuple2#(tLen, tLen) divideLenByChunk(tLen len, tChunk chunk),
        function Bool isAddrAndLengthLowerPartSumOverflow(tLen len, tChunk chunk),
        function tLen getChunkSize(tChunk chunk)
    )(AddressChunkMetaCalculator#(tAddr, tLen, tChunk, tMaxChunkSizeWidth)) provisos (
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
    FIFOF#(AddressChunkMeta#(tAddr, tLen, tChunk, tMaxChunkSizeWidth)) respMetaQ <- mkFIFOF;

    // Pipeline FIFOs
    FIFOF#(Tuple6#(AddressChunkReq#(tAddr, tLen, tChunk), tLen, Tuple5#(Bool, Bool, Bool, Bool, Bool), tInternalMathOp, tInternalMathOp, tAddr)) preCalcPipelineQ <- mkFIFOF;

    rule preCalculate;

        let req = reqQ.first;
        reqQ.deq;

        let {devidedLen, lenRemainderTmp} = divideLenByChunk(req.len, req.chunk);
        let {alignedAddr, addrRemainderTmp} = alignAddrByChunk(req.startAddr, req.chunk);
        tInternalMathOp chunkSize = unpack(truncate(pack(getChunkSize(req.chunk))));

        tInternalMathOp lenRemainder = unpack(truncate(pack(lenRemainderTmp)));
        tInternalMathOp addrRemainder = unpack(truncate(pack(addrRemainderTmp)));
        
        tLen zeroBasedChunkNum = ?;
        
        tInternalMathOp tmpSumResult = lenRemainder + addrRemainder;

        let lenRemainderIsZero = isZeroR(pack(lenRemainder));
        let addrRemainderIsZero = isZeroR(pack(addrRemainder));
        let devidedLenIsZero = isZeroR(pack(devidedLen));
        let devidedLenIsOne = isOneR(pack(devidedLen));
        let isAddrAndLengthLowerPartSumOverflowResult = isAddrAndLengthLowerPartSumOverflow(unpack(zeroExtend(pack(tmpSumResult))), req.chunk);
        
        let nextAddr = alignedAddr + unpack(zeroExtend(pack(chunkSize)));  // should we extract it to a function to reduce add bits?

        let pipeLineEntry = tuple6(
            req,
            devidedLen, 
            tuple5(lenRemainderIsZero, addrRemainderIsZero, isAddrAndLengthLowerPartSumOverflowResult, devidedLenIsZero, devidedLenIsOne),
            chunkSize,
            addrRemainder,
            nextAddr
        );
        preCalcPipelineQ.enq(pipeLineEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressChunkMetaCalculator preCalculate"),
        //     toBlue(", req="), fshow(req),
        //     toBlue(", devidedLen="), fshow(devidedLen),
        //     toBlue(", chunkSize="), fshow(chunkSize),
        //     toBlue(", addrRemainder="), fshow(addrRemainder),
        //     toBlue(", nextAddr="), fshow(nextAddr)
        // );
    endrule

    rule outputMeta;

        let {req, devidedLen, boolTuple, chunkSize, addrRemainder, nextAddr} = preCalcPipelineQ.first;
        let {lenRemainderIsZero, addrRemainderIsZero, isAddrAndLengthLowerPartSumOverflowResult, devidedLenIsZero, devidedLenIsOne} = boolTuple;
        preCalcPipelineQ.deq;

        tLen zeroBasedChunkNum = ?;
        let isOnlyChunk = False;

        if (addrRemainderIsZero && lenRemainderIsZero) begin
            zeroBasedChunkNum = devidedLen - 1;
            if (devidedLenIsOne) begin
                isOnlyChunk = True;
            end
        end
        else if (addrRemainderIsZero && !lenRemainderIsZero) begin
            zeroBasedChunkNum = devidedLen;
            if (devidedLenIsZero) begin
                isOnlyChunk = True;
            end
        end
        else if (!addrRemainderIsZero && lenRemainderIsZero) begin
            zeroBasedChunkNum = devidedLen;
            if (devidedLenIsZero) begin
                isOnlyChunk = True;
            end
        end
        else begin
            if (isAddrAndLengthLowerPartSumOverflowResult) begin
                zeroBasedChunkNum = devidedLen + 1;
            end
            else begin
                zeroBasedChunkNum = devidedLen;
                if (devidedLenIsZero) begin
                    isOnlyChunk = True;
                end
            end
        end


        let outMeta = AddressChunkMeta{
            zeroBasedChunkNum: zeroBasedChunkNum,
            req: req,
            devidedLen: devidedLen,
            chunkSize: chunkSize,
            addrRemainder: addrRemainder,
            nextAddr: nextAddr,
            isOnlyChunk: isOnlyChunk
        };

        respMetaQ.enq(outMeta);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressChunkMetaCalculator outputMeta"),
        //     toBlue(", outMeta="), fshow(outMeta)
        // );

    endrule

    interface requestPipeIn = toPipeIn(reqQ);
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
            (len[8] == 1 && !isZeroR(len[7 : 0]));
        end
        IBV_MTU_512 : begin
            // 9 = log2(512)
            (len[9] == 1 && !isZeroR(len[8 : 0]));
        end
        IBV_MTU_1024: begin
            // 10 = log2(1024)
            (len[10] == 1 && !isZeroR(len[9 : 0]));
        end
        IBV_MTU_2048: begin
            // 11 = log2(2048)
            (len[11] == 1 && !isZeroR(len[10 : 0]));
        end
        IBV_MTU_4096: begin
            // 12 = log2(4096)
            (len[12] == 1 && !isZeroR(len[11 : 0]));
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


// since the pcie burst is a const value, so no need to return value dynamically. Only need a placeholder to satify function signature.
typedef Bit#(0) PcieAddressChunkTypeDontCarePlaceHolder; 
typedef TLog#(PCIE_NAP_MAX_BYTE_IN_BURST) PCIE_BURST_ALIGN_BIT_NUM;   // 9

function Tuple2#(ADDR, ADDR) alignAddrForPcieBurst(ADDR addr, PcieAddressChunkTypeDontCarePlaceHolder _dontcare);
    Bit#(PCIE_BURST_ALIGN_BIT_NUM) zeroPadding = 0;
    ADDR alignedAddr = unpack({addr[valueOf(ADDR_WIDTH)-1 : valueOf(PCIE_BURST_ALIGN_BIT_NUM)], zeroPadding});
    ADDR addrRemainder = unpack({zeroPadding, addr[valueOf(PCIE_BURST_ALIGN_BIT_NUM) - 1 : 0]});
    return tuple2(alignedAddr, addrRemainder);
endfunction

function Tuple2#(Length, Length) devideLengthForPcieBurst(Length len, PcieAddressChunkTypeDontCarePlaceHolder _dontcare);
    Bit#(PCIE_BURST_ALIGN_BIT_NUM) zeroPadding = 0;
    Length dividedLen = {zeroPadding, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : valueOf(PCIE_BURST_ALIGN_BIT_NUM)]};
    Length divideRemainder = {zeroPadding, len[valueOf(PCIE_BURST_ALIGN_BIT_NUM) - 1 : 0]};
    return tuple2(dividedLen, divideRemainder);
endfunction

function Bool isAddrAndLengthLowerPartSumOverflowForPcieBurst(Length len, PcieAddressChunkTypeDontCarePlaceHolder _dontcare);
    Bit#(PCIE_BURST_ALIGN_BIT_NUM) lowerBits = len[valueOf(PCIE_BURST_ALIGN_BIT_NUM)-1 : 0];
    return len[valueOf(PCIE_BURST_ALIGN_BIT_NUM)] == 1 && !isZeroR(lowerBits);
endfunction

function Length getChunkSizeForPcieBurst(PcieAddressChunkTypeDontCarePlaceHolder _dontcare);
    return fromInteger(valueOf(PCIE_NAP_MAX_BYTE_IN_BURST));
endfunction


// since the beat size is a const value, so no need to return value dynamically. Only need a placeholder to satify function signature.
typedef Bit#(0) BeatAddressChunkTypeDontCarePlaceHolder; 
typedef TLog#(NOC_DATA_BUS_BYTE_WIDTH) BEAT_ALIGN_BIT_NUM;   // 5

function Tuple2#(ADDR, ADDR) alignAddrForBeat(ADDR addr, BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
    Bit#(BEAT_ALIGN_BIT_NUM) zeroPadding = 0;
    ADDR alignedAddr = unpack({addr[valueOf(ADDR_WIDTH)-1 : valueOf(BEAT_ALIGN_BIT_NUM)], zeroPadding});
    ADDR addrRemainder = unpack({zeroPadding, addr[valueOf(BEAT_ALIGN_BIT_NUM) - 1 : 0]});
    return tuple2(alignedAddr, addrRemainder);
endfunction

function Tuple2#(Length, Length) devideLengthForBeat(Length len, BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
    Bit#(BEAT_ALIGN_BIT_NUM) zeroPadding = 0;
    Length dividedLen = {zeroPadding, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : valueOf(BEAT_ALIGN_BIT_NUM)]};
    Length divideRemainder = {zeroPadding, len[valueOf(BEAT_ALIGN_BIT_NUM) - 1 : 0]};
    return tuple2(dividedLen, divideRemainder);
endfunction

function Bool isAddrAndLengthLowerPartSumOverflowForBeat(Length len, BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
    Bit#(BEAT_ALIGN_BIT_NUM) lowerBits = len[valueOf(BEAT_ALIGN_BIT_NUM)-1 : 0];
    return len[valueOf(BEAT_ALIGN_BIT_NUM)] == 1 && !isZeroR(lowerBits);
endfunction

function Length getChunkSizeForBeat(BeatAddressChunkTypeDontCarePlaceHolder _dontcare);
    return fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH));
endfunction
