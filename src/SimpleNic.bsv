import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;

import Settings :: *;
import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import AddressChunker :: *;
import RdmaHeaders :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import Ringbuf :: *;
import Descriptors :: *;
import EthernetTypes :: *;


typedef 2048    SIMPLE_NIC_SLOT_BYTE_SIZE;
typedef 2097152 SIMPLE_NIC_BUFFER_BYTE_SIZE;
typedef 512     SIMPLE_NIC_RX_PER_CHANNEL_BUFFER_DEPTH;

typedef TDiv#(SIMPLE_NIC_BUFFER_BYTE_SIZE, SIMPLE_NIC_SLOT_BYTE_SIZE) SIMPLE_NIC_SLOT_CNT;
typedef TLog#(SIMPLE_NIC_SLOT_CNT) SIMPLE_NIC_SLOT_INDEX_WITDH;
typedef TAdd#(1, SIMPLE_NIC_SLOT_INDEX_WITDH)  SIMPLE_NIC_SLOT_COUNT_WITDH;
typedef Bit#(SIMPLE_NIC_SLOT_INDEX_WITDH) SimpleNicSlotIdx;
typedef Bit#(SIMPLE_NIC_SLOT_COUNT_WITDH) SimpleNicSlotCnt;
typedef TDiv#(SIMPLE_NIC_SLOT_BYTE_SIZE, TLog#(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE)) SIMPLE_NIC_STREAM_ALIGN_BLOCK_CNT_PER_SLOT;
typedef Bit#(TAdd#(1, TLog#(SIMPLE_NIC_STREAM_ALIGN_BLOCK_CNT_PER_SLOT))) AlignBlockCntInSimpleNicSlot;

interface SimpleNic;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(IoChannelEthDataStream)) rawEthernetPacketPipeInVec;
    interface PipeOut#(IoChannelEthDataStream)                                  rawEthernetPacketPipeOut;
    
    interface PipeIn#(RingbufRawDescriptor)                                     simpleNicTxDescPipeIn;
    interface PipeOut#(RingbufRawDescriptor)                                    simpleNicRxDescPipeOut;
    interface IoChannelMemoryMasterPipe                                         simpleNicPacketDmaMasterPipeIfc;
endinterface

(* synthesize *)
module mkSimpleNic(SimpleNic);
    Reg#(SimpleNicSlotIdx) curSlotIdxReg <- mkReg(0);
    Reg#(ADDR) rxBufferBaseAddrReg <- mkReg(0);
    
    Vector#(HARDWARE_QP_CHANNEL_CNT, FIFOF#(IoChannelEthDataStream)) rawEthernetPacketPipeInQueueVec <- replicateM(mkLFIFOF);

    Vector#(HARDWARE_QP_CHANNEL_CNT, FIFOF#(Word)) rawEthernetPacketLengthQueueVec <- replicateM(mkSizedFIFOF(valueOf(NUMERIC_TYPE_EIGHT)));
    Vector#(HARDWARE_QP_CHANNEL_CNT, Reg#(Word)) rawEthernetPacketLengthRegVec <- replicateM(mkReg(0));

    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(IoChannelEthDataStream)) rawEthernetPacketPipeInVecInst = newVector;
    FIFOF#(IoChannelEthDataStream) rawEthernetPacketPipeOutQueue <- mkLFIFOF;



    FIFOF#(RingbufRawDescriptor) simpleNicDescPipeInQueue <- mkLFIFOF;
    FIFOF#(RingbufRawDescriptor) simpleNicDescPipeOutQueue <- mkLFIFOF;

    FIFOF#(IoChannelMemoryAccessMeta)           dmaWriteMetaPipeOutQueue    <- mkLFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream)     dmaWriteDataPipeOutQueue    <- mkLFIFOF;
    FIFOF#(IoChannelMemoryAccessMeta)           dmaReadMetaPipeOutQueue     <- mkLFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream)     dmaReadDataPipeInQueue      <- mkLFIFOF;

    DtldStreamNoMetaArbiterSlave#(HARDWARE_QP_CHANNEL_CNT, DATA) ethStreamArbiter <- mkDtldStreamNoMetaArbiterSlave(valueOf(HARDWARE_QP_CHANNEL_CNT));

    AddressChunker#(ADDR, Length, ChunkAlignLogValue) rxAddrChunker <- mkAddressChunker;
    AddressChunker#(ADDR, Length, ChunkAlignLogValue) txAddrChunker <- mkAddressChunker;

    DtldStreamConcator#(DATA, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) txConcator <- mkDtldStreamConcator;
    DtldStreamSplitor#(DATA, AlignBlockCntInSimpleNicSlot, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) rxSplitor <- mkDtldStreamSplitor;

    // Pipeline FIFO
    FIFOF#(AddressChunkResp#(ADDR, Length)) forwardRxChunkedDataStreamToDmaPipelineQ <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_FOUR));
    FIFOF#(Tuple2#(SimpleNicSlotIdx, Word)) rxDescMetaPipelineQ <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_FOUR));

    mkConnection(ethStreamArbiter.pipeOutIfc, rxSplitor.dataPipeIn);
    mkConnection(toPipeOut(dmaReadDataPipeInQueue), txConcator.dataPipeIn);
    mkConnection(txConcator.dataPipeOut, toPipeIn(rawEthernetPacketPipeOutQueue));

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        rawEthernetPacketPipeInVecInst[idx] = toPipeIn(rawEthernetPacketPipeInQueueVec[idx]);

        rule calcPacketLenAndPutToBuffer;
            let ds = rawEthernetPacketPipeInQueueVec[idx].first;
            rawEthernetPacketPipeInQueueVec[idx].deq;
            ethStreamArbiter.pipeInIfcVec[idx].enq(ds);

            let newLength = rawEthernetPacketLengthRegVec[idx] + zeroExtend(ds.byteNum);

            if (ds.isLast) begin
                rawEthernetPacketLengthRegVec[idx] <= 0;
                rawEthernetPacketLengthQueueVec[idx].enq(newLength);
            end
            else begin
                rawEthernetPacketLengthRegVec[idx] <= newLength;
            end
        endrule
    end

    rule forwardRxDsLengthToChunkCalc;
        let selChannel = ethStreamArbiter.sourceChannelIdPipeOut.first;
        ethStreamArbiter.sourceChannelIdPipeOut.deq;

        let totalLen = rawEthernetPacketLengthQueueVec[selChannel].first;
        rawEthernetPacketLengthQueueVec[selChannel].deq;

        ADDR writeAddr = rxBufferBaseAddrReg + (zeroExtend(curSlotIdxReg) << valueOf(TLog#(SIMPLE_NIC_SLOT_BYTE_SIZE)));
        curSlotIdxReg <= curSlotIdxReg + 1;
        rxAddrChunker.requestPipeIn.enq(AddressChunkReq{
            startAddr: writeAddr,
            len: zeroExtend(totalLen),
            chunk: fromInteger(valueOf(TLog#(PCIE_NAP_MAX_BYTE_IN_BURST)))
        });
        rxDescMetaPipelineQ.enq(tuple2(curSlotIdxReg, totalLen));
    endrule

    rule forwardRxDmaChunkSplitReq;
        let chunkInfo = rxAddrChunker.responsePipeOut.first;
        rxAddrChunker.responsePipeOut.deq;
        let alignBlockCntForDmaBurst = (chunkInfo.len + fromInteger(valueOf(TExp#(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE)) - 1)) >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE);
        rxSplitor.streamAlignBlockCountPipeIn.enq(truncate(alignBlockCntForDmaBurst));
        forwardRxChunkedDataStreamToDmaPipelineQ.enq(chunkInfo);
    endrule

    rule forwardRxChunkedDataStreamToDma;
        let ds = rxSplitor.dataPipeOut.first;
        rxSplitor.dataPipeOut.deq;
        let chunkInfo = forwardRxChunkedDataStreamToDmaPipelineQ.first;
        if (ds.isFirst) begin
            let wm = IoChannelMemoryAccessMeta{
                addr        : chunkInfo.startAddr,
                totalLen    : chunkInfo.len
            };
            dmaWriteMetaPipeOutQueue.enq(wm);
        end
        if (ds.isLast) begin
            forwardRxChunkedDataStreamToDmaPipelineQ.deq;

            if (chunkInfo.isLast) begin
                let {slotIdx, totalLen} = rxDescMetaPipelineQ.first;
                rxDescMetaPipelineQ.deq;
                
                let commonHeader = RingbufDescCommonHead {
                    valid           : True,
                    hasNextFrag     : False,
                    reserved0       : unpack(0),
                    isExtendOpcode  : True,  // since it's not standard rdma opcode
                    opCode          : fromInteger(valueOf(SIMPLE_NIC_RX_QUEUE_DESC_OPCODE_NEW_PACKET))
                };

                simpleNicDescPipeOutQueue.enq(pack(SimpleNicRxQueueDesc {
                    reserved3   : unpack(0),
                    reserved2   : unpack(0),
                    reserved1   : unpack(0),
                    slotIdx     : zeroExtend(slotIdx),
                    len         : zeroExtend(totalLen),
                    reserved0   : unpack(0),
                    commonHeader: commonHeader   
                }));

            end
        end
        dmaWriteDataPipeOutQueue.enq(ds);
    endrule


    rule handleTxReq;
        SimpleNicTxQueueDesc desc = unpack(pack(simpleNicDescPipeInQueue.first));
        simpleNicDescPipeInQueue.deq;

        txAddrChunker.requestPipeIn.enq(AddressChunkReq {
            startAddr: desc.addr,
            len: desc.len,
            chunk: fromInteger(valueOf(TLog#(PCIE_NAP_MAX_BYTE_IN_BURST)))
        });
    endrule

    rule handleTxAddrChunkResp;
        let chunkInfo = txAddrChunker.responsePipeOut.first;
        txAddrChunker.responsePipeOut.deq;

        dmaReadMetaPipeOutQueue.enq(IoChannelMemoryAccessMeta{
            addr: chunkInfo.startAddr,
            totalLen: chunkInfo.len
        });
        txConcator.isLastStreamFlagPipeIn.enq(chunkInfo.isLast);
    endrule





    interface rawEthernetPacketPipeInVec = rawEthernetPacketPipeInVecInst;
    interface rawEthernetPacketPipeOut = toPipeOut(rawEthernetPacketPipeOutQueue);
    interface simpleNicTxDescPipeIn = toPipeIn(simpleNicDescPipeInQueue);
    interface simpleNicRxDescPipeOut = toPipeOut(simpleNicDescPipeOutQueue);

    interface IoChannelMemoryMasterPipe simpleNicPacketDmaMasterPipeIfc;
        interface DtldStreamMasterWritePipes  writePipeIfc;
            interface writeMetaPipeOut  = toPipeOut(dmaWriteMetaPipeOutQueue);
            interface writeDataPipeOut  = toPipeOut(dmaWriteDataPipeOutQueue);
        endinterface
        interface DtldStreamMasterReadPipes  readPipeIfc;
            interface readMetaPipeOut   = toPipeOut(dmaReadMetaPipeOutQueue);
            interface readDataPipeIn    = toPipeIn(dmaReadDataPipeInQueue);
        endinterface
    endinterface
endmodule