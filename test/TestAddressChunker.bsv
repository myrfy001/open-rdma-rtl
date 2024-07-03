import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;


(* doc = "testcase" *)
module mkTestAddressChunker(Empty);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);
    AddressChunker#(ADDR, Length, PMTU, TAdd#(1, MAX_PMTU_WIDTH)) dut <- mkAddressChunker(
        alignAddrByPMTU,
        devideLengthByPMTU,
        isAddrAndLengthLowerPartSumOverflowPMTU,
        getChunkSizeForPMTU
    );

    PipeOut#(Length) pmtuRandPipeOut <- mkRandomLenPipeOut(1, 5);
    PipeOut#(Length) lengthRandPipeOut <- mkRandomLenPipeOut(1, 1024 * 16);
    PipeOut#(ADDR) addrRandPipeOut <- mkGenericRandomPipeOut;

    FIFOF#(AddressChunkReq#(ADDR, Length, PMTU)) expectedQ <- mkFIFOF;

    Reg#(AddressChunkReq#(ADDR, Length, PMTU)) curCheckingReqReg <- mkRegU;
    Reg#(Length) totalLenSumReg <- mkRegU;
    Reg#(Bool) canGenReqReg <- mkReg(True);

    rule reqGen if (canGenReqReg);
        canGenReqReg <= False;
        PMTU pmtu = unpack(truncate(pack(pmtuRandPipeOut.first)));
        pmtuRandPipeOut.deq;

        Length len = lengthRandPipeOut.first;
        lengthRandPipeOut.deq;

        ADDR addr = addrRandPipeOut.first;
        addrRandPipeOut.deq;

        let isAccepted = True;

        Bit#(TAdd#(1, SizeOf#(ADDR))) addrPlusLen = zeroExtend(addr) + zeroExtend(len);
        
        if (msb(addrPlusLen) == 1) begin
            isAccepted = False;
        end

        if (isAccepted) begin
            let req = AddressChunkReq{
                startAddr: addr,
                len: len,
                chunk: pmtu 
            };

            dut.requestPipeIn.enq(req);
            expectedQ.enq(req);
        end

    endrule

    rule checkResp if (!canGenReqReg);
        let chunk = dut.responsePipeOut.first;
        dut.responsePipeOut.deq;

        let meta = ?;

        let expectedReq = curCheckingReqReg;
        let totalLenSum = totalLenSumReg;
        if (chunk.isFirst) begin
            expectedReq = expectedQ.first;
            curCheckingReqReg <= expectedReq;
            expectedQ.deq;

            meta = dut.metaPipeOut.first;
            dut.metaPipeOut.deq;
            totalLenSum = chunk.len;
        end
        else begin
            totalLenSum = totalLenSum + chunk.len;
        end
        totalLenSumReg <= totalLenSum;


        Length pamuInByteNum = 128 << pack(expectedReq.chunk);



        if (chunk.isFirst && chunk.isLast) begin
            immAssert(
                meta.zeroBasedChunkNum == 0,
                "For ONLY chunk, meta.zeroBasedChunkNum should be zero.",
                $format("Got meta=", fshow(meta))
            );

            immAssert(
                chunk.len == expectedReq.len,
                "For ONLY chunk, expect chunk.len == expectedReq.len",
                $format("Got chunk=", fshow(chunk), ", expectedReq=", fshow(expectedReq))
            );
        end

        if (chunk.isFirst) begin
            immAssert(
                chunk.startAddr == expectedReq.startAddr,
                "For first chunk, the start address must match the request's start address",
                $format("Got chunk=", fshow(chunk), ", expectedReq=", fshow(expectedReq))
            );
        end

        immAssert(
            chunk.len <= pamuInByteNum && chunk.len != 0,
            "resp chunk len must not greater than req chunk size, and must not be zero",
            $format("Got chunk=", fshow(chunk), ", pamuInByteNum=", fshow(pamuInByteNum))
        );

        let {devidedLen, lenRemainderTmp} = devideLengthByPMTU(chunk.len, expectedReq.chunk);
        let {alignedAddr, addrRemainderTmp} = alignAddrByPMTU(chunk.startAddr, expectedReq.chunk);
        immAssert(
            lenRemainderTmp + truncate(addrRemainderTmp) <= pamuInByteNum,
            "a split should not across align boundary.",
            $format(
                "lenRemainderTmp=", fshow(lenRemainderTmp), 
                ", addrRemainderTmp=", fshow(addrRemainderTmp),
                ", pamuInByteNum=", fshow(pamuInByteNum)
            ) 
        );

        if (!chunk.isFirst) begin
            immAssert(
                addrRemainderTmp == 0,
                "address not aligned",
                $format(
                    ", addrRemainderTmp=", fshow(addrRemainderTmp)
                ) 
            );
        end

        if (!chunk.isFirst && !chunk.isLast) begin
            immAssert(
                chunk.len == pamuInByteNum,
                "middle chunk shoud have full length",
                $format(
                    "lenRemainderTmp=", fshow(lenRemainderTmp), 
                    ", addrRemainderTmp=", fshow(addrRemainderTmp),
                    ", expectedReq=", fshow(expectedReq)
                ) 
            );
        end

        if (chunk.isLast) begin
            immAssert(
                totalLenSum == expectedReq.len,
                "totalLenSum should match expectedReq.len",
                $format(
                    "totalLenSum=", fshow(totalLenSum), 
                    ", expectedReq=", fshow(expectedReq)
                ) 
            );
        end

        if (chunk.isLast) begin
            quitCounterReg <= quitCounterReg - 1;
            canGenReqReg <= True;
            if (quitCounterReg % 100000 == 0) begin
                $display("quitCounterReg=%d",quitCounterReg);
            end
            if (quitCounterReg == 0) begin
                $display("Pass");
                $finish;
            end
        end

    endrule
endmodule



interface TestAddressChunkerTiming;
    method Bit#(512) getOutput;
endinterface



(* synthesize *)
(* doc = "testcase" *)
module mkTestAddressChunkerTiming(TestAddressChunkerTiming);
    
    AddressChunker#(ADDR, Length, PMTU, TAdd#(1, MAX_PMTU_WIDTH)) dut <- mkAddressChunker(
        alignAddrByPMTU,
        devideLengthByPMTU,
        isAddrAndLengthLowerPartSumOverflowPMTU,
        getChunkSizeForPMTU
    );

    Reg#(PMTU) chunkSizeReg <- mkRegU;
    Reg#(ADDR) addrReg <- mkReg(0);
    Reg#(Length) lengthReg <- mkReg(0);

    Reg#(AddressChunkResp#(ADDR, Length)) outReg <- mkRegU;

    rule t;
        chunkSizeReg <= unpack(pack(chunkSizeReg) + 1);
        addrReg <= (addrReg << 1)  + zeroExtend(pack(chunkSizeReg));
        lengthReg <= truncate(addrReg);
    endrule

    rule injectInput1;
        dut.requestPipeIn.enq(
            AddressChunkReq{
                startAddr: addrReg,
                len: lengthReg,
                chunk: chunkSizeReg 
            });
    endrule


    
    rule merge;
        let t1 = dut.responsePipeOut.first;
        dut.responsePipeOut.deq;
        let t2 = dut.metaPipeOut.first;
        dut.metaPipeOut.deq;

        outReg <= unpack(pack(t1) ^ zeroExtend(pack(t2)));
    endrule

    method getOutput = zeroExtend(pack(outReg));
endmodule