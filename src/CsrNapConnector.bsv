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
import CsrFramework :: *;
import Ringbuf :: *;

typedef 7 CSR_ADDR_WIDTH;
typedef 32 CSR_DATA_WIDTH;

typedef 5  CSR_BAR_ADDR_TO_INNER_ADDR_ALIGN_OFFSET;

typedef Bit#(CSR_ADDR_WIDTH) CsrAddr;
typedef Bit#(CSR_DATA_WIDTH) CsrData;

typedef CsrLeafAccessor#(CsrAddr, CsrData) RdmaCsrLeafAccessor;
typedef CsrSwitch#(CsrAddr, CsrData) RdmaCsrSwitch;
typedef CsrReadWriteReq#(CsrAddr, CsrData) RdmaCsrReadWriteReq;


module mkCsrRootSwitch(CsrSwitch#(CsrAddr, CsrData, downStreamPortCnt));
    AcxNapMasterWrapperPipe napInst <- mkAcxNapMasterWrapperPipe;
    CsrSwitch#(CsrAddr, CsrData, downStreamPortCnt) innerSwitch <- mkPipelineCsrSwitch;

    FIFOF#(NapAxiRid) axiRidKeepOrderQ <- mkFIFOF;


    rule forwardReadOrWriteReq;

        if (napInst.readPipeIfc.readAddrPipeOut.notEmpty) begin
            let rawReadReq = napInst.readPipeIfc.readAddrPipeOut.first;
            napInst.readPipeIfc.readAddrPipeOut.deq;

            RdmaCsrReadWriteReq req = RdmaCsrReadWriteReq {
                addr: truncate(rawReadReq.araddr >> valueOf(CSR_BAR_ADDR_TO_INNER_ADDR_ALIGN_OFFSET)),
                value: ?,
                isWrite: False
            };
            innerSwitch.busInputSrv.request.put(req);
            $display("bbbbbb=", fshow(req));
            axiRidKeepOrderQ.enq(rawReadReq.arid);
        end
        else if (napInst.writePipeIfc.writeAddrPipeOut.notEmpty && napInst.writePipeIfc.writeDataPipeOut.notEmpty) begin
            let rawWriteAddrReq = napInst.writePipeIfc.writeAddrPipeOut.first;
            napInst.writePipeIfc.writeAddrPipeOut.deq;
            let rawWriteDataReq = napInst.writePipeIfc.writeDataPipeOut.first;
            napInst.writePipeIfc.writeDataPipeOut.deq;

            RdmaCsrReadWriteReq req = RdmaCsrReadWriteReq {
                addr: truncate(rawWriteAddrReq.awaddr >> valueOf(CSR_BAR_ADDR_TO_INNER_ADDR_ALIGN_OFFSET)),
                value: truncate(rawWriteDataReq.wdata),
                isWrite: True
            };
            innerSwitch.busInputSrv.request.put(req);
            $display("aaaaa=", fshow(req));

            napInst.writePipeIfc.writeRespPipeIn.enq(AxiMmNapBeatB {
                bid: rawWriteAddrReq.awid,
                bresp: 0
            });
        end
    endrule

    rule forwardReadResp;
        let resp <- innerSwitch.busInputSrv.response.get;
        let rid = axiRidKeepOrderQ.first;
        axiRidKeepOrderQ.deq;

        immAssert(
            isValid(resp.valueMaybe),
            "mkCsrRootSwitch, read resp not vaild, maybe CSR address not match",
            $format("")
        );

        let axiResp = AxiMmNapBeatR {
            rid: rid,
            rdata: zeroExtend(fromMaybe(?, resp.valueMaybe)),
            rresp: 0,
            rlast: True
        };
        napInst.readPipeIfc.readRespPipeIn.enq(axiResp);
    endrule

    interface CsrReadWriteSrvIfc busInputSrv;
        interface Put request;
            method Action put(CsrReadWriteReq#(tAddr, tValue) req);
                immFail("Not supported on Root Switch", $format(""));
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(CsrReadWriteResp#(tValue)) get;
                immFail("Not supported on Root Switch", $format(""));
                return ?;
            endmethod
        endinterface
    endinterface
    interface busOutputCltVecIfc = innerSwitch.busOutputCltVecIfc;
endmodule
    


module mkConnectionCsrAccessorAndRingbuf#(
        RdmaCsrLeafAccessor csrAccessorSqBaseAddrLow,
        RdmaCsrLeafAccessor csrAccessorSqBaseAddrHigh,
        RdmaCsrLeafAccessor csrAccessorSqHead,
        RdmaCsrLeafAccessor csrAccessorSqTail,
        RingbufSlot4096Meta ringBufCsr
    )(Empty ifc);

    Reg#(ADDR32) baseAddrLowReg <- mkReg(0);
    Reg#(ADDR32) baseAddrHighReg <- mkReg(0);

    rule connectBaseAddrLow;
        baseAddrLowReg <= csrAccessorSqBaseAddrLow.writeValOut;
    endrule

    rule connectBaseAddrHigh;
        baseAddrHighReg <= csrAccessorSqBaseAddrHigh.writeValOut;
    endrule

    rule combineLowAndHighAddr;
        ringBufCsr.addr <= {baseAddrHighReg, baseAddrLowReg};
    endrule

    rule connectHeadWrite;
        ringBufCsr.head <= unpack(truncate(csrAccessorSqHead.writeValOut));
    endrule

    rule connectHeadRead;
        csrAccessorSqHead.readValIn(zeroExtend(pack(ringBufCsr.head)));
    endrule

    rule connectTailWrite;
        ringBufCsr.tail <= unpack(truncate(csrAccessorSqTail.writeValOut));
    endrule

    rule connectTailRead;
        csrAccessorSqTail.readValIn(zeroExtend(pack(ringBufCsr.tail)));
    endrule
endmodule