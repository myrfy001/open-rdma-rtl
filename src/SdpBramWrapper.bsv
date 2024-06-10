import GetPut :: *;
import ClientServer :: *;
import Connectable :: *;
import RegFile :: *;
import FIFOF :: *;
import Vector :: *;

import PrimUtils :: *;


typedef 14 ACX_BRAM72K_SDP_ADDR_WIDTH;
typedef Bit#(ACX_BRAM72K_SDP_ADDR_WIDTH) AcxBram72kAddr;
typedef TMul#(72,1024) BITS_COUNT_72K;

typedef Bit#(144) Bram72kEntry144;
typedef Bit#(128) Bram72kEntry128;

interface BRAM72K_SDP#(type tData);
    method Action putReadReq(AcxBram72kAddr addr);
    method tData read;
    method Action putWriteReq(AcxBram72kAddr addr, tData data);    
endinterface


import "BVI" ACX_BRAM72K_SDP =
module mkBram72kSdpVerilogInner(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData)
           );

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    parameter read_width  = valueOf(szData);
    parameter write_width = valueOf(szData);
    parameter byte_width = 8;
    parameter outreg_enable = 1;
    
    input_clock wrClk (wrclk) = clk;
    input_clock rdClk (rdclk) = clk;
    input_reset outLatchRst(outlatch_rstn) = rst;
    input_reset outRegRst(outreg_rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    port we = 18'h3FFFF;
    port wrmsel = 1'b0;
    port rdmsel = 1'b0;
    port outreg_ce = 1'b1;


    method putReadReq((*reg*)rdaddr) enable(rden) clocked_by(rdClk) reset_by(no_reset);
    method dout read clocked_by(rdClk) reset_by(no_reset);
    method putWriteReq((*reg*)wraddr, (*reg*)din) enable(wren) clocked_by(wrClk) reset_by(no_reset);    

    schedule putReadReq C putReadReq;
    schedule read CF read;
    schedule putWriteReq C putWriteReq;
    schedule (putReadReq) CF (read);
    // schedule (putReadReq) CF (putWriteReq);
    // schedule (putReadReq, putWriteReq) SB read;

endmodule



module mkBram72kSdpVerilog(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData)
           );

    function ActionValue#(Integer) getAddrShift;
        return actionvalue
            Integer ret = 0;
            case (valueOf(szData))
                144, 128 : ret = 5;
                72 , 64  : ret = 4;
                36 , 32  : ret = 3;
                18 , 16  : ret = 2;
                9  ,  8  : ret = 1;
                4        : ret = 0;
                default  :
                    immFail("mkBram72kSdpVerilog", $format("BRAM72k data width not supported: %d", valueOf(szData)));
            endcase
            return ret;
        endactionvalue;
    endfunction

    BRAM72K_SDP#(tData) inner <- mkBram72kSdpVerilogInner;
    
    method Action putReadReq(AcxBram72kAddr addr);
        let shiftCnt <- getAddrShift;
        inner.putReadReq(addr << shiftCnt);
    endmethod
    
    method read = inner.read;

    method Action putWriteReq(AcxBram72kAddr addr, tData data);
        let shiftCnt <- getAddrShift;
        inner.putWriteReq(addr << shiftCnt, data);
    endmethod

endmodule




// bluesim module for the BVI imported ACX_BRAM72K_SDP
module mkBram72kSdpBluesim(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData),
            Add#(a__, szData, BITS_COUNT_72K)
    );

    RegFile#(AcxBram72kAddr, tData) storage <- mkRegFileFull;
    
    Reg#(tData) outDataDelayReg1 <- mkRegU;
    Reg#(tData) outDataDelayReg2 <- mkRegU;

    RWire#(Tuple2#(AcxBram72kAddr, tData)) writeReqWire <- mkRWire;
    RWire#(AcxBram72kAddr) readReqWire <- mkRWire;


    rule handle;
        if (writeReqWire.wget matches tagged Valid .req) begin
            let {addr, data} = req;
            storage.upd(addr, data);
        end

        if (readReqWire.wget matches tagged Valid .addr) begin
            outDataDelayReg1 <= storage.sub(addr);
        end

        outDataDelayReg2 <= outDataDelayReg1;

    endrule

    method Action putReadReq(AcxBram72kAddr addr);
        readReqWire.wset(addr);
    endmethod
    
    method read = outDataDelayReg2;

    method Action putWriteReq(AcxBram72kAddr addr, tData data);
        writeReqWire.wset(tuple2(addr, data));
    endmethod    

endmodule

module mkBRAM72K_SDP(BRAM72K_SDP#(tData))
    provisos(
            Bits#(tData, szData),
            Add#(a__, szData, BITS_COUNT_72K)
    );

    BRAM72K_SDP#(tData) _i;
    if (genVerilog) begin
        _i <- mkBram72kSdpVerilog;
    end
    else begin
        _i <- mkBram72kSdpBluesim;
    end
    return _i;
endmodule

interface SdpBram#(type tData);
    interface Put#(Tuple2#(AcxBram72kAddr, tData)) write;
    interface Server#(AcxBram72kAddr, tData) readSrv;
endinterface

module mkSdpBram(SdpBram#(tData)) provisos (
        Bits#(AcxBram72kAddr, szAddr),
        Bits#(tData, szData),
        Bounded#(AcxBram72kAddr),
        Eq#(AcxBram72kAddr),
        Add#(a__, szData, BITS_COUNT_72K)
    );

    BRAM72K_SDP#(tData) ram <- mkBRAM72K_SDP;


    FIFOF#(Tuple2#(AcxBram72kAddr, tData)) writeReqQ1 <- mkUGLFIFOF;
    FIFOF#(Tuple2#(AcxBram72kAddr, tData)) writeReqQ2 <- mkUGLFIFOF;

    FIFOF#(AcxBram72kAddr) readAddrQ1  <- mkUGLFIFOF;
    FIFOF#(AcxBram72kAddr) readAddrQ2  <- mkUGLFIFOF;

    FIFOF#(tData) outQ <- mkUGSizedFIFOF(4);
    FIFOF#(Bit#(0)) backPressureQ <- mkUGFIFOF;

    rule doDelay;
        if (readAddrQ1.notEmpty && readAddrQ2.notFull) begin
            readAddrQ2.enq(readAddrQ1.first);
            readAddrQ1.deq;
        end

        if (writeReqQ1.notEmpty && writeReqQ2.notFull) begin
            writeReqQ2.enq(writeReqQ1.first);
            writeReqQ1.deq;
        end
    endrule

    (* no_implicit_conditions *)
    rule checkConflict;
        Maybe#(AcxBram72kAddr) writeReqMaybe = tagged Invalid;
        Maybe#(AcxBram72kAddr) readReqMaybe = tagged Invalid;
        let {addr, data} = ?;
        if (writeReqQ2.notEmpty) begin
            writeReqQ2.deq;
            {addr, data} = writeReqQ2.first;
            writeReqMaybe = tagged Valid addr;
        end

        if (readAddrQ2.notEmpty) begin
            readAddrQ2.deq;
            readReqMaybe = tagged Valid readAddrQ2.first;
        end
    
        Bool isAddrConflict = (
            isValid(writeReqMaybe) && 
            isValid(readReqMaybe)  &&
            fromMaybe(?, writeReqMaybe) == fromMaybe(?, readReqMaybe)
        );

        Bool hasReadReqInThisBeat = readAddrQ2.notEmpty;

        if (hasReadReqInThisBeat) begin
            if (isAddrConflict) begin
                outQ.enq(data);
            end
            else begin
                outQ.enq(ram.read);
            end
            backPressureQ.enq(0);
        end
        

    endrule

    interface Put write;
        method Action put(Tuple2#(AcxBram72kAddr, tData) req);
            let {addr, data} = req;
            immAssert(writeReqQ1.notFull, "UG FIFO writeReqQ1 is Full when trying to enq", $format(""));
            ram.putWriteReq(addr, data);
            writeReqQ1.enq(tuple2(addr,data));
        endmethod
    endinterface

    interface Server readSrv;
        interface Put request;
            method Action put(AcxBram72kAddr addr) if (backPressureQ.notFull);
                ram.putReadReq(addr);
                immAssert(readAddrQ1.notFull, "UG FIFO readAddrQ1 is Full when trying to enq", $format(""));
                readAddrQ1.enq(addr);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(tData) get if (outQ.notEmpty);
                outQ.deq;
                backPressureQ.deq;
                return outQ.first;
            endmethod
        endinterface
    endinterface
endmodule    