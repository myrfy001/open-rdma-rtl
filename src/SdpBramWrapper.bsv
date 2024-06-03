import GetPut :: *;
import ClientServer :: *;
import RegFile :: *;
import FIFOF :: *;

interface BRAM72K_SDP#(type tAddr, type tData);
    method Action putReadReq(tAddr addr);
    method tData read;
    method Action putWriteReq(tAddr addr, tData data);    
endinterface


import "BVI" ACX_BRAM72K_SDP =
module vBRAM72K_SDP(BRAM72K_SDP#(tAddr, tData))
    provisos(
            Bits#(tAddr, szAddr),
            Bits#(tData, szData)
           );

    let clk <- exposeCurrentClock;
    parameter read_width  = 144;
    parameter write_width = 144;
    parameter byte_width = 8;
    parameter outreg_enable = 1;
    
    input_clock wrClk (wrclk) = clk;
    input_clock rdCLk (rdclk) = clk;
    default_clock no_clock;
    no_reset;

    port we = -1;
    port wrmsel = 0;


    method putReadReq(rdaddr) enable(rden) clocked_by(rdCLk) reset_by(no_reset);
    method dout read clocked_by(rdCLk) reset_by(no_reset);
    method putWriteReq(wraddr, din) enable(wren) clocked_by(wrClk) reset_by(no_reset);    

    schedule putReadReq C putReadReq;
    schedule read CF read;
    schedule putWriteReq C putWriteReq;
    schedule (putReadReq) CF (read);
    // schedule (putReadReq) CF (putWriteReq);
    // schedule (putReadReq, putWriteReq) SB read;

endmodule

interface SdpBram#(type tAddr, type tData);
    interface Put#(Tuple2#(tAddr, tData)) write;
    interface Server#(tAddr, tData) readSrv;
endinterface

module mkSdpBram(SdpBram#(tAddr, tData)) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tData, szData),
        Bounded#(tAddr),
        Eq#(tAddr)
    );

    BRAM72K_SDP#(tAddr, tData) ram <- vBRAM72K_SDP;
    RWire#(tAddr) writeAddrWire <- mkRWire;
    RWire#(tData) writeDataWire <- mkRWire;
    RWire#(tAddr) readAddrWire  <- mkRWire;

    Reg#(Maybe#(tData)) writeDelayStep1Reg <- mkReg(tagged Invalid);
    Reg#(Maybe#(tData)) writeDelayStep2Reg <- mkReg(tagged Invalid);
    
    Reg#(Bool) readDelayStep1Reg <- mkReg(False);
    Reg#(Bool) readDelayStep2Reg <- mkReg(False);

    FIFOF#(tData) outQ <- mkSizedFIFOF(4);
    FIFOF#(Bit#(0)) backPressureQ <- mkFIFOF;

    rule putWriteToDelayPipeline;
        Bool isAddrConflict = (
            isValid(writeAddrWire.wget) && 
            isValid(readAddrWire.wget)  &&
            fromMaybe(?, writeAddrWire.wget) == fromMaybe(?, readAddrWire.wget)
        );
        writeDelayStep1Reg <= isAddrConflict ? writeDataWire.wget : tagged Invalid;
        writeDelayStep2Reg <= writeDelayStep1Reg;
    endrule

    rule putReadToDelayPipeline;
        readDelayStep1Reg <= isValid(readAddrWire.wget);
        readDelayStep2Reg <= readDelayStep1Reg;
    endrule

    rule readBramOutToOutQ;
        let hasValidOutputThisCycle = readDelayStep2Reg;
        if (hasValidOutputThisCycle) begin
            if (writeDelayStep2Reg matches tagged Valid .data) begin
                // Valid means read and write conflict, need use bypass data
                outQ.enq(data);
            end
            else begin
                outQ.enq(ram.read);
            end
            backPressureQ.enq(0);
        end
    endrule

    interface Put write;
        method Action put(Tuple2#(tAddr, tData) req);
            let {addr, data} = req;
            ram.putWriteReq(addr, data);
            writeAddrWire.wset(addr);
            writeDataWire.wset(data);
        endmethod
    endinterface

    interface Server readSrv;
        interface Put request;
            method Action put(tAddr addr) if (backPressureQ.notFull);
                ram.putReadReq(addr);
                readAddrWire.wset(addr);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(tData) get;
                outQ.deq;
                backPressureQ.deq;
                return outQ.first;
            endmethod
        endinterface
    endinterface
endmodule    