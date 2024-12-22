import Vector :: *;
import Settings :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
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

import IoChannels :: *;
import ConnectableF :: *;
import CsrFramework :: *;
import Ringbuf :: *;

typedef 7 CSR_ADDR_WIDTH;
typedef 32 CSR_DATA_WIDTH;

typedef 5  CSR_BAR_ADDR_TO_INNER_ADDR_ALIGN_OFFSET;

typedef Bit#(CSR_ADDR_WIDTH) CsrAddr;
typedef Bit#(CSR_DATA_WIDTH) CsrData;


interface CsrRootConnector;
    interface IoChannelMemorySlavePipe dmaSidePipeIfc;
    interface CsrNodeDownStreamPort#(CsrAddr, CsrData) csrNodeRootPortIfc;
endinterface

(* synthesize *)
module mkCsrRootConnector(CsrRootConnector);
   
    FIFOF#(IoChannelMemoryAccessMeta)       busReadMetaPipeInQueue  <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream) busReadDataPipeOutQueue <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessMeta)       busWriteMetaPipeInQueue <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream) busWriteDataPipeInQueue <- mkFIFOF;

    FIFOF#(CsrReadWriteReq#(CsrAddr, CsrData))  csrReqQueue <- mkFIFOF;
    FIFOF#(CsrReadWriteResp#(CsrData))          csrRespQueue <- mkFIFOF;
    
    rule forwardReadOrWriteReq;
        if (busReadMetaPipeInQueue.notEmpty) begin
            let readMeta = busReadMetaPipeInQueue.first;
            busReadMetaPipeInQueue.deq;
            csrReqQueue.enq(CsrReadWriteReq{
                addr: truncate(readMeta.addr),
                value: ?,
                isWrite: False
            });
        end
        else if (busWriteMetaPipeInQueue.notEmpty && busWriteDataPipeInQueue.notEmpty) begin
            let writeMeta = busWriteMetaPipeInQueue.first;
            busWriteMetaPipeInQueue.deq;
            let writeData = busWriteDataPipeInQueue.first;
            busWriteDataPipeInQueue.deq;

            let req = CsrReadWriteReq {
                addr: truncate(writeMeta.addr),
                value: truncate(writeData.data),
                isWrite: True
            };
            csrReqQueue.enq(req);
        end
    endrule

    rule forwardReadResp;
        let resp = csrRespQueue.first;
        csrRespQueue.deq;
        busReadDataPipeOutQueue.enq(DataStream{
            data: zeroExtend(resp.value),
            byteNum: fromInteger(valueOf(TDiv#(CSR_DATA_WIDTH, BYTE_WIDTH))),
            startByteIdx: 0,
            isFirst: True,
            isLast: True
        });
    endrule

    interface IoChannelMemorySlavePipe dmaSidePipeIfc;
        interface DtldStreamSlaveWritePipes writePipeIfc;
            interface writeMetaPipeIn = toPipeIn(busWriteMetaPipeInQueue);
            interface writeDataPipeIn = toPipeIn(busWriteDataPipeInQueue);
        endinterface
        interface DtldStreamSlaveReadPipes readPipeIfc;
            interface readMetaPipeIn = toPipeIn(busReadMetaPipeInQueue);
            interface readDataPipeOut = toPipeOut(busReadDataPipeOutQueue);
        endinterface
    endinterface
    interface csrNodeRootPortIfc = toGPClient(csrReqQueue, csrRespQueue);
endmodule
    
typedef CsrNode#(CsrAddr, CsrData, NUMERIC_TYPE_ZERO)   CsrNodeLeaf;
typedef CsrNode#(CsrAddr, CsrData, NUMERIC_TYPE_ONE)    CsrNodeFork1;
typedef CsrNode#(CsrAddr, CsrData, NUMERIC_TYPE_TWO)    CsrNodeFork2;
typedef CsrNode#(CsrAddr, CsrData, NUMERIC_TYPE_FOUR)   CsrNodeFork4;
typedef CsrNode#(CsrAddr, CsrData, NUMERIC_TYPE_EIGHT)  CsrNodeFork8;

typedef CsrReadWriteReq#(CsrAddr, CsrData) CsrAccessReq;

typedef CsrNodeResult#(Bit#(TLog#(NUMERIC_TYPE_ONE)), CsrData) CsrNodeResultLeaf;
typedef CsrNodeResult#(Bit#(TLog#(NUMERIC_TYPE_ONE)), CsrData) CsrNodeResultFork1;
typedef CsrNodeResult#(Bit#(TLog#(NUMERIC_TYPE_TWO)), CsrData) CsrNodeResultFork2;
typedef CsrNodeResult#(Bit#(TLog#(NUMERIC_TYPE_FOUR)), CsrData) CsrNodeResultFork4;
typedef CsrNodeResult#(Bit#(TLog#(NUMERIC_TYPE_EIGHT)), CsrData) CsrNodeResultFork8;
