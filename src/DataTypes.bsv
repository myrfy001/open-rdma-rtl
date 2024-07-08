import ClientServer :: *;
import PAClib :: *;
import PrimUtils :: *;
import Vector :: *;
import GetPut :: *;

import RdmaHeaders :: *;
import Settings :: *;
import EthernetTypes :: *;

typedef 1 NUMERIC_TYPE_ONE;
typedef 2 NUMERIC_TYPE_TWO;
typedef 3 NUMERIC_TYPE_THREE;
typedef 4 NUMERIC_TYPE_FOUR;
typedef 5 NUMERIC_TYPE_FIVE;
typedef 6 NUMERIC_TYPE_SIX;
typedef 7 NUMERIC_TYPE_SEVEN;
typedef 8 NUMERIC_TYPE_EIGHT;




typedef 3 BIT_BYTE_CONVERT_SHIFT_NUM;
typedef 8 BYTE_WIDTH;
typedef 16 WORD_WIDTH;
typedef Bit#(BYTE_WIDTH) Byte;
typedef Bit#(WORD_WIDTH) Word;

// Protocol settings
typedef TExp#(31) RDMA_MAX_LEN;
typedef 8         ATOMIC_WORK_REQ_LEN;
typedef 3         RETRY_CNT_WIDTH;

typedef 7 INFINITE_RETRY;
typedef 0 INFINITE_TIMEOUT;

typedef TMul#(8192, TExp#(30)) MAX_TIMEOUT_NS; // 2^43
typedef TMul#(655360, 1000)    MAX_RNR_WAIT_NS; // 2^30

typedef 16'hFFFF     DEFAULT_PKEY;
typedef 32'hFFFFFFFF DEFAULT_QKEY;
typedef 3            DEFAULT_RETRY_NUM;

typedef 64 ATOMIC_ADDR_BIT_ALIGNMENT;

typedef 32 PD_HANDLE_WIDTH;

typedef 8 QP_CAP_CNT_WIDTH;
// typedef 32 QP_CAP_CNT_WIDTH;
// typedef 8 PENDING_READ_ATOMIC_REQ_CNT_WIDTH;

// Derived settings
typedef AETH_VALUE_WIDTH TIMER_WIDTH;

typedef TLog#(MAX_SGE)          SGE_IDX_WIDTH;
typedef TAdd#(1, SGE_IDX_WIDTH) SGE_NUM_WIDTH;

// 12 + 4 + 16 + 16 = 48 bytes
typedef TAdd#(TAdd#(BTH_BYTE_WIDTH, XRCETH_BYTE_WIDTH), TAdd#(RETH_BYTE_WIDTH, LETH_BYTE_WIDTH)) RDMA_HEADER_MAX_BYTE_LENGTH;
typedef 42 ETH_IP_UDP_HEADER_BYTE_LENGTH; // 14(MAC) + 20(IP) + 8(UDP) = 42
typedef TAdd#(ETH_IP_UDP_HEADER_BYTE_LENGTH, RDMA_HEADER_MAX_BYTE_LENGTH) ETH_IP_UDP_RDMA_HEADER_MAX_BYTE_LENGTH;
typedef TAdd#(ETH_IP_UDP_RDMA_HEADER_MAX_BYTE_LENGTH, MAX_PMTU) RDMA_ETHERNET_FRAME_MAX_BYTE_LENGTH;
typedef Bit#(TAdd#(1, TLog#(RDMA_ETHERNET_FRAME_MAX_BYTE_LENGTH))) RdmaEthernetFrameByteLen;

typedef TDiv#(DATA_BUS_WIDTH, 8)   DATA_BUS_BYTE_WIDTH; // 32 (bus 256b), 64 (bus 512b)
typedef TLog#(DATA_BUS_BYTE_WIDTH) DATA_BUS_BYTE_NUM_WIDTH; // 5 (bus 256b), 6 (bus 512b)
typedef TLog#(DATA_BUS_WIDTH)      DATA_BUS_BIT_NUM_WIDTH; // 8 (bus 256b), 9 (bus 512b)


typedef TLog#(MAX_PMTU)                      MAX_PMTU_WIDTH; // 12
// typedef TLog#(TLog#(MAX_PMTU))               PMTU_VALUE_MAX_WIDTH; // 4
typedef TDiv#(MAX_PMTU, DATA_BUS_BYTE_WIDTH) PMTU_MAX_FRAG_NUM; // 128 (bus 256b), 64 (bus 512b)
typedef TDiv#(MIN_PMTU, DATA_BUS_BYTE_WIDTH) PMTU_MIN_FRAG_NUM; // 8 (bus 256b), 4 (bus 512b)

typedef TAdd#(1, TSub#(RDMA_MAX_LEN_WIDTH, TLog#(DATA_BUS_BYTE_WIDTH))) TOTAL_FRAG_NUM_WIDTH; // 28 (bus 256b), 27 (bus 512b)
typedef TAdd#(1, TLog#(PMTU_MAX_FRAG_NUM))                              PMTU_FRAG_NUM_WIDTH; // 8
typedef TAdd#(1, TSub#(RDMA_MAX_LEN_WIDTH, TLog#(MIN_PMTU)))            PKT_NUM_WIDTH; // 25
typedef TAdd#(1, TLog#(MAX_PMTU))                                       PKT_LEN_WIDTH; // 13

typedef TDiv#(ATOMIC_ADDR_BIT_ALIGNMENT, BYTE_WIDTH) ATOMIC_ADDR_BYTE_ALIGNMENT; // 8

typedef TExp#(PAD_WIDTH) FRAG_MIN_VALID_BYTE_NUM; // 4

typedef TMul#(MIN_PKT_NUM_IN_RECV_BUF, PMTU_MAX_FRAG_NUM)   DATA_STREAM_FRAG_BUF_SIZE;
typedef TDiv#(DATA_STREAM_FRAG_BUF_SIZE, PMTU_MIN_FRAG_NUM) PKT_META_DATA_BUF_SIZE;

typedef TDiv#(MAX_RNR_WAIT_NS, TARGET_CYCLE_NS) MAX_RNR_WAIT_CYCLES;
typedef TLog#(MAX_RNR_WAIT_CYCLES)              RNR_WAIT_CYCLE_CNT_WIDTH;
typedef TDiv#(MAX_TIMEOUT_NS, TARGET_CYCLE_NS)  MAX_TIMEOUT_CYCLES;
typedef TAdd#(1, TLog#(MAX_TIMEOUT_CYCLES))     TIMEOUT_CYCLE_CNT_WIDTH;

typedef 48                                            PHYSICAL_ADDR_WIDTH; // X86 physical address width
typedef TLog#(PAGE_SIZE_CAP)                          PAGE_OFFSET_WIDTH;
typedef TSub#(PHYSICAL_ADDR_WIDTH, PAGE_OFFSET_WIDTH) PAGE_NUMBER_WIDTH;   // 48-21=27
typedef Bit#(PAGE_OFFSET_WIDTH)  PageOffset;
typedef Bit#(PAGE_NUMBER_WIDTH)  PageNumber;
typedef Bit#(PHYSICAL_ADDR_WIDTH) PADDR;

typedef TExp#(14) TLB_CACHE_SIZE; // TLB cache size 16K
typedef TLog#(TLB_CACHE_SIZE) TLB_CACHE_INDEX_WIDTH; // 14
typedef TSub#(TSub#(ADDR_WIDTH, TLB_CACHE_INDEX_WIDTH), PAGE_OFFSET_WIDTH) TLB_CACHE_TAG_WIDTH; // 64-14-21=29

typedef TLog#(MAX_MR) MR_INDEX_WIDTH;
typedef TSub#(KEY_WIDTH, MR_INDEX_WIDTH) MR_KEY_PART_WIDTH;

// Derived types
typedef Bit#(DATA_BUS_WIDTH)      DATA;
typedef Bit#(DATA_BUS_BYTE_WIDTH) ByteEn;

typedef Bit#(SGE_IDX_WIDTH) IdxSGL;
typedef Bit#(SGE_NUM_WIDTH) NumSGE;


typedef Bit#(DATA_BUS_BIT_NUM_WIDTH)  BusBitWidthMask; // 8 (bus 256b), 9 (bus 512b)
typedef Bit#(DATA_BUS_BYTE_NUM_WIDTH) BusByteWidthMask; // 5 (bus 256b), 6 (bus 512b)
// typedef Bit#(PAD_WIDTH)               PadMask;

typedef Bit#(TAdd#(1, DATA_BUS_BIT_NUM_WIDTH))  BusBitNum; // 9 (bus 256b), 10 (bus 512b)
typedef Bit#(TAdd#(1, DATA_BUS_BYTE_NUM_WIDTH)) ByteEnBitNum; // 6 (bus 256b), 7 (bus 512b)

typedef ByteEnBitNum DataBusOneBasedByteIndex;          // 6 (bus 256b), 7 (bus 512b)
typedef ByteEnBitNum DataBusSignedShiftOffset;          // 6 (bus 256b), 7 (bus 512b)
typedef Bit#(DATA_BUS_BYTE_NUM_WIDTH) DataBusShiftOffset; // 5 (bus 256b), 6 (bus 512b)
typedef Bit#(DATA_BUS_BYTE_NUM_WIDTH) ByteIndexInBeat; // 5 (bus 256b), 6 (bus 512b)

typedef TMul#(2, DATA_BUS_BYTE_WIDTH) BYTE_NUM_OF_TWO_BEATS;            // 64
typedef TMul#(3, DATA_BUS_BYTE_WIDTH) BYTE_NUM_OF_THREE_BEATS;          // 96

typedef Bit#(QP_CAP_CNT_WIDTH) PendingReqCnt;
typedef Bit#(QP_CAP_CNT_WIDTH) InlineDataSize;
typedef Bit#(QP_CAP_CNT_WIDTH) ScatterGatherElemCnt;

typedef Bit#(MAX_PMTU_WIDTH)       ResiduePMTU;
typedef Bit#(TAdd#(1, MAX_PMTU_WIDTH)) ByteNumPMTU;
typedef Bit#(TOTAL_FRAG_NUM_WIDTH) TotalFragNum;
typedef Bit#(PMTU_FRAG_NUM_WIDTH)  PktFragNum;
typedef Bit#(PKT_NUM_WIDTH)        PktNum;
typedef Bit#(PKT_LEN_WIDTH)        PktLen;

typedef Bit#(RETRY_CNT_WIDTH) RetryCnt;
typedef Bit#(TIMER_WIDTH)     TimeOutTimer;
typedef Bit#(TIMER_WIDTH)     RnrTimer;

typedef Bit#(TLog#(ATOMIC_ADDR_BYTE_ALIGNMENT)) AtomicAddrByteAlignment;

typedef Bit#(RNR_WAIT_CYCLE_CNT_WIDTH) RnrWaitCycleCnt;
typedef Bit#(TIMEOUT_CYCLE_CNT_WIDTH)  TimeOutCycleCnt;

typedef Bit#(PD_HANDLE_WIDTH) HandlerPD;

typedef PipeOut#(DataStream) DataStreamPipeOut;
typedef Put#(DataStream) DataStreamPipeIn;

typedef Tuple3#(DataStream, Bool, RecvPacketSrcMacIpBufferIdx) RqDataStreamWithExtraInfo;
typedef PipeOut#(RqDataStreamWithExtraInfo) RqDataStreamWithExtraInfoPipeOut;
typedef Put#(RqDataStreamWithExtraInfo) RqDataStreamWithExtraInfoPipeIn;

typedef PipeOut#(RecvReq)                     RecvReqBuf;


typedef Bit#(TLog#(MAX_PTE_ENTRY_CNT)) PTEIndex;

typedef struct {
    PTEIndex pgtOffset;
    ADDR baseVA;
    Length len;
    FlagsType#(MemAccessTypeFlag) accFlags;
    HandlerPD pdHandler;
    KeyPartMR keyPart;
} MemRegionTableEntry deriving(Bits, FShow);

typedef struct {
    PageNumber pn;
} PageTableEntry deriving(Bits, FShow);

typedef struct {
    IndexMR idx;
    Maybe#(MemRegionTableEntry) entry;
} MrTableModifyReq deriving(Bits, FShow);

typedef struct {
    Bool success;
} MrTableModifyResp deriving(Bits, FShow);

typedef struct {
    IndexMR idx;
} MrTableQueryReq deriving(Bits, FShow);

typedef struct {
    PTEIndex idx;
    PageTableEntry pte;
} PgtModifyReq deriving(Bits, FShow);

typedef struct {
    Bool success;
} PgtModifyResp deriving(Bits, FShow);

typedef struct {
    PTEIndex pgtOffset;
    ADDR baseVA;
    ADDR addrToTrans;
} PgtAddrTranslateReq deriving(Bits, FShow);


typedef Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) MrTableQueryClt;
typedef Client#(PgtAddrTranslateReq, ADDR) PgtQueryClt;

// Common types

typedef Server#(DmaReadReq, DmaReadResp)            DmaReadSrv;
typedef Server#(DmaWriteReq, DmaWriteResp)    DmaWriteSrv;
typedef Client#(DmaReadReq, DmaReadResp)            DmaReadClt;
typedef Client#(DmaWriteReq, DmaWriteResp)    DmaWriteClt;

typedef Server#(PermCheckReq, Bool) PermCheckSrv;
typedef Client#(PermCheckReq, Bool) PermCheckClt;

// interface RdmaPktMetaDataAndQpcAndPayloadPipeOut;
//     interface PipeOut#(RdmaPktMetaDataAndQPC) pktMetaData;
//     interface DataStreamFragMetaPipeOut payloadStreamFragMetaPipeOut;
// endinterface

// RDMA related requests and responses

// typedef enum {
//     RDMA_RESP_NORMAL,
//     RDMA_RESP_RETRY,
//     RDMA_RESP_ERROR,
//     RDMA_RESP_UNKNOWN
// } RdmaRespType deriving(Bits, Eq, FShow);

// typedef enum {
//     RETRY_REASON_NOT_RETRY,
//     RETRY_REASON_RNR,
//     RETRY_REASON_SEQ_ERR,
//     RETRY_REASON_IMPLICIT,
//     RETRY_REASON_TIMEOUT
// } RetryReason deriving(Bits, Eq, FShow);

// DATA are right aligned for first and only beat, and are left aligned for middle and last beat
// startByteIdx is valid when isFirst = True, and in other case, startByteIdx must be 0
// For the recv side, currently the received payload is already aligned to the receiver side address,
// so no shift is need at received side, in this case, both byteNum and startByteIdx is useless, since 
// the valid bytes in first and last beat can be calculated from RDMA RETH's address and length.
// But for the send side, it need to shift data to match recv side address, so byteNum and startByteIdx
// is needed. startByteIdx is need only for "ONLY beat" datastream when doing right shift.
// for example, if a datastream has only one beat, and it's valid byte has something like:
// 00000XXXXXX000
// since it has some invalid byte at it's lower bits, when doing right shift, if the shift is small, it won't 
// need another beat, but if shift is large, it may need a second beat to hold the overflow bits. so only when doing 
// right shift with only beat, the startByteIdx is necessary.
typedef struct {
    DATA               data;
    ByteEnBitNum       byteNum;
    ByteIndexInBeat    startByteIdx;
    Bool               isFirst;
    Bool               isLast;
} DataStream deriving(Bits, Bounded, Eq, FShow);

// DATA and ByteEn are left aligned
typedef struct {
    DATA data;
    ByteEn byteEn;
    Bool isFirst;
    Bool isLast;
} DataStreamEn deriving(Bits, FShow);

// This buffer should be able to contain the largest extend header combinations.
// For now, the largest one is 36 Byte;
typedef 288 RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH;
typedef Bit#(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) RdmaExtendHeaderBuffer;
typedef TDiv#(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH, BYTE_WIDTH) RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH;        // 36
typedef TAdd#(1, TLog#(RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH)) RDMA_EXTEND_HEADER_LENGTH_BIT_WIDTH;          // 6
typedef Bit#(RDMA_EXTEND_HEADER_LENGTH_BIT_WIDTH) RdmaExtendHeaderLength;

typedef TAdd#(RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH, BTH_BYTE_WIDTH) RDMA_BTH_AND_ETH_MAX_BYTE_WIDTH;        // 44
typedef TAdd#(1, TLog#(RDMA_BTH_AND_ETH_MAX_BYTE_WIDTH)) RDMA_BTH_AND_ETH_MAX_LENGTH_WIDTH;                 // 7    TODO: should reduce to 6?
typedef Bit#(RDMA_BTH_AND_ETH_MAX_LENGTH_WIDTH) RdmaBthAndEthTotalLength;


typedef struct {
    BTH bth;
    RdmaExtendHeaderBuffer rdmaExtendHeaderBuf;
} RdmaBthAndExtendHeader deriving(Bits, Eq, FShow);

typedef struct {
    RdmaBthAndExtendHeader header;
    Bool hasPayload;
} RdmaRecvPacketMeta deriving(Bits, FShow);

typedef struct {
    PktFragNum beatCnt;
} RdmaRecvPacketTailMeta deriving(Bits, FShow);

typedef struct {
    RdmaBthAndExtendHeader header;
    Bool hasPayload;
} RdmaSendPacketMeta deriving(Bits, FShow);


// typedef struct {
//     HeaderByteNum                   headerLen;
//     HeaderFragNum                   headerFragNum;
//     ByteEnBitNum                    lastFragValidByteNum;
//     Bool                            hasPayload;
//     Bool                            isEmptyHeader;
//     RecvPacketSrcMacIpBufferIdx     srcMacIpIdx;
// } HeaderMetaData deriving(Bits, Bounded, Eq);

// typedef struct {
//     ByteEnBitNum lastFragValidByteNum;
// } PayloadMetaData deriving(Bits, Bounded, Eq);

// instance FShow#(HeaderMetaData);
//     function Fmt fshow(HeaderMetaData hmd);
//         return $format(
//             "HeaderMetaData { headerLen=%0d, headerFragNum=%0d, lastFragValidByteNum=%0d, hasPayload=",
//             hmd.headerLen, hmd.headerFragNum, hmd.lastFragValidByteNum, fshow(hmd.hasPayload), " }"
//         );
//     endfunction
// endinstance

// // HeaderData and HeaderByteEn are left aligned
// typedef struct {
//     HeaderData                headerData;
//     HeaderByteNum              headerByteNum;
//     HeaderMetaData            headerMetaData;
// } HeaderRDMA deriving(Bits, Bounded, FShow);

// typedef enum {
//     PKT_ST_VALID,
//     PKT_ST_LEN_ERR
//     // PKT_ST_QP_ACC_ERR,
//     // PKT_ST_DISCARD
// } PktVeriStatus deriving(Bits, Bounded, Eq, FShow);

// typedef struct {
//     PktLen pktPayloadLen;
//     PktFragNum pktFragNum;
//     Bool isZeroPayloadLen;
//     HeaderRDMA pktHeader;
//     Bool pktValid;
//     PktVeriStatus pktStatus;
// } RdmaPktMetaData deriving(Bits, Bounded);

// instance FShow#(RdmaPktMetaData);
//     function Fmt fshow(RdmaPktMetaData rpmd);
//         return $format(
//             "RdmaPktMetaData { pktPayloadLen=%0d, pktFragNum=%0d",
//             rpmd.pktPayloadLen, rpmd.pktFragNum,
//             ", pktHeader=", fshow(rpmd.pktHeader),
//             ", pktValid=", fshow(rpmd.pktValid), " }"
//         );
//     endfunction
// endinstance

// DMA related

typedef struct {
    // Maybe#(WorkReqID) wrID;  // TODO: remove it
    LKEY lkey;
    RKEY rkey;
    Bool localOrRmtKey; // True for local, False for remote
    ADDR reqAddr;
    Length totalLen;
    HandlerPD pdHandler;
    Bool isZeroDmaLen;
    FlagsType#(MemAccessTypeFlag) accFlags;
} PermCheckReq deriving(Bits, FShow);

typedef struct {
    ADDR startAddr;
    Length len;
    IndexMR mrIdx;
} DmaReadMetaData deriving(Bits, FShow);

typedef struct {
    ADDR startAddr;
    PktLen len;
    IndexMR mrIdx;
} DmaReadReq deriving(Bits, FShow);

typedef struct {
    Bool isRespErr;
    DataStream dataStream;
} DmaReadResp deriving(Bits, FShow);

typedef struct {
    ADDR startAddr;
    PktLen len;
} DmaWriteMetaData deriving(Bits, Eq, FShow);

typedef struct {
    DmaWriteMetaData metaData;
    DataStream dataStream;
} DmaWriteReq deriving(Bits, FShow);

typedef struct {
        Bool isRespErr;
} DmaWriteResp deriving(Bits, FShow);

typedef enum {
    DMA_SRC_RQ_RD,
    DMA_SRC_RQ_WR,
    DMA_SRC_RQ_DUP_RD,
    DMA_SRC_RQ_ATOMIC,
    DMA_SRC_RQ_DISCARD,
    // DMA_SRC_RQ_CANCEL,
    DMA_SRC_SQ_RD,
    DMA_SRC_SQ_WR,
    DMA_SRC_SQ_ATOMIC,
    DMA_SRC_SQ_DISCARD
    // DMA_SRC_SQ_CANCEL
} DmaReqSrcType deriving(Bits, Eq, FShow); // TODO: remove it


typedef struct {
    DmaReqSrcType initiator;
    Bool casOrFetchAdd;
    ADDR startAddr;
    Long compData;
    Long swapData;
    QPN sqpn;
    PSN psn;
} AtomicOpReq deriving(Bits);

typedef struct {
    DmaReqSrcType initiator;
    Long original;
    QPN sqpn;
    PSN psn;
} AtomicOpResp deriving(Bits);

// QP related types

typedef enum {
    IBV_QPS_RESET,
    IBV_QPS_INIT,
    IBV_QPS_RTR,
    IBV_QPS_RTS,
    IBV_QPS_SQD,
    IBV_QPS_SQE,
    IBV_QPS_ERR,
    IBV_QPS_UNKNOWN,
    IBV_QPS_CREATE // TODO: remote it. Not defined in rdma-core
} StateQP deriving(Bits, Eq, FShow);

typedef enum {
    IBV_QPT_RC         = 2,
    IBV_QPT_UC         = 3,
    IBV_QPT_UD         = 4,
    IBV_QPT_RAW_PACKET = 8,
    IBV_QPT_XRC_SEND   = 9,
    IBV_QPT_XRC_RECV   = 10
    // IBV_QPT_DRIVER = 0xff
} TypeQP deriving(Bits, Eq, FShow);

typedef enum {
    IBV_ACCESS_NO_FLAGS      =  0, // Not defined in rdma-core
    IBV_ACCESS_LOCAL_WRITE   =  1, // (1 << 0)
    IBV_ACCESS_REMOTE_WRITE  =  2, // (1 << 1)
    IBV_ACCESS_REMOTE_READ   =  4, // (1 << 2)
    IBV_ACCESS_REMOTE_ATOMIC =  8, // (1 << 3)
    IBV_ACCESS_MW_BIND       = 16, // (1 << 4)
    IBV_ACCESS_ZERO_BASED    = 32, // (1 << 5)
    IBV_ACCESS_ON_DEMAND     = 64, // (1 << 6)
    IBV_ACCESS_HUGETLB       = 128 // (1 << 7)
    // IBV_ACCESS_RELAXED_ORDERING    = IBV_ACCESS_OPTIONAL_FIRST,
} MemAccessTypeFlag deriving(Bits, Eq, FShow);

instance Flags#(MemAccessTypeFlag);
    function Bool isOneHotOrZero(MemAccessTypeFlag inputVal) = 1 >= countOnes(pack(inputVal));
endinstance

typedef enum {
    IBV_MTU_256  = 1,
    IBV_MTU_512  = 2,
    IBV_MTU_1024 = 3,
    IBV_MTU_2048 = 4,
    IBV_MTU_4096 = 5
} PMTU deriving(Bits, Eq, FShow);

typedef struct {
    PendingReqCnt        maxSendWR;
    PendingReqCnt        maxRecvWR;
    ScatterGatherElemCnt maxSendSGE;
    ScatterGatherElemCnt maxRecvSGE;
    InlineDataSize       maxInlineData;
} QpCapacity deriving(Bits, FShow);

typedef struct {
    StateQP                       qpState;
    StateQP                       curQpState;
    PMTU                          pmtu;
    QKEY                          qkey;
    PSN                           rqPSN;
    PSN                           sqPSN;
    QPN                           dqpn;
    FlagsType#(MemAccessTypeFlag) qpAccessFlags;
    QpCapacity                    cap;
    PKEY                          pkeyIndex;
    Bool                          sqDraining;
    PendingReqCnt                 maxReadAtomic;
    PendingReqCnt                 maxDestReadAtomic;
    RnrTimer                      minRnrTimer;
    TimeOutTimer                  timeout;
    RetryCnt                      retryCnt;
    RetryCnt                      rnrRetry;
    // PKEY                          alt_pkey_index;
    // enum ibv_mig_state            path_mig_state;
    // struct ibv_ah_attr            ah_attr;
    // struct ibv_ah_attr            alt_ah_attr;
    // uint8_t                       en_sqd_async_notify;
    // uint8_t                       port_num;
    // uint8_t                       alt_port_num;
    // uint8_t                       alt_timeout;
    // uint32_t                      rate_limit;
} AttrQP deriving(Bits, FShow);

typedef struct {
    TypeQP qpType;
    Bool   sqSigAll;
} QpInitAttr deriving(Bits, FShow);

typedef enum {
    IBV_QP_NO_FLAGS            = 0,       // Not defined in rdma-core
    IBV_QP_STATE               = 1,       // 1 << 0
    IBV_QP_CUR_STATE           = 2,       // 1 << 1
    IBV_QP_EN_SQD_ASYNC_NOTIFY = 4,       // 1 << 2
    IBV_QP_ACCESS_FLAGS        = 8,       // 1 << 3
    IBV_QP_PKEY_INDEX          = 16,      // 1 << 4
    IBV_QP_PORT                = 32,      // 1 << 5
    IBV_QP_QKEY                = 64,      // 1 << 6
    IBV_QP_AV                  = 128,     // 1 << 7
    IBV_QP_PATH_MTU            = 256,     // 1 << 8
    IBV_QP_TIMEOUT             = 512,     // 1 << 9
    IBV_QP_RETRY_CNT           = 1024,    // 1 << 10
    IBV_QP_RNR_RETRY           = 2048,    // 1 << 11
    IBV_QP_RQ_PSN              = 4096,    // 1 << 12
    IBV_QP_MAX_QP_RD_ATOMIC    = 8192,    // 1 << 13
    IBV_QP_ALT_PATH            = 16384,   // 1 << 14
    IBV_QP_MIN_RNR_TIMER       = 32768,   // 1 << 15
    IBV_QP_SQ_PSN              = 65536,   // 1 << 16
    IBV_QP_MAX_DEST_RD_ATOMIC  = 131072,  // 1 << 17
    IBV_QP_PATH_MIG_STATE      = 262144,  // 1 << 18
    IBV_QP_CAP                 = 524288,  // 1 << 19
    IBV_QP_DEST_QPN            = 1048576, // 1 << 20
    // These bits were supported on older kernels, but never exposed from libibverbs
    // _IBV_QP_SMAC               = 1 << 21,
    // _IBV_QP_ALT_SMAC           = 1 << 22,
    // _IBV_QP_VID                = 1 << 23,
    // _IBV_QP_ALT_VID            = 1 << 24,
    IBV_QP_RATE_LIMIT          = 33554432 // 1 << 25
} QpAttrMaskFlag deriving(Bits, Eq, FShow);

instance Flags#(QpAttrMaskFlag);
    function Bool isOneHotOrZero(QpAttrMaskFlag inputVal) = 1 >= countOnes(pack(inputVal));
endinstance


typedef TLog#(MAX_QP) QP_INDEX_WIDTH;
typedef TSub#(QPN_WIDTH, QP_INDEX_WIDTH) QPN_KEY_PART_WIDTH;

typedef UInt#(QP_INDEX_WIDTH)     IndexQP;
typedef UInt#(QPN_KEY_PART_WIDTH) KeyQP;


function IndexQP getIndexQP(QPN qpn) = unpack(truncateLSB(qpn));
function KeyQP   getKeyQP  (QPN qpn) = unpack(truncate(qpn));

function QPN genQPN(IndexQP qpIndex, KeyQP qpKey);
    return { pack(qpIndex), pack(qpKey) };
endfunction


// WorkReq related

typedef enum {
    IBV_WR_RDMA_WRITE           =  0,
    IBV_WR_RDMA_WRITE_WITH_IMM  =  1,
    IBV_WR_SEND                 =  2,
    IBV_WR_SEND_WITH_IMM        =  3,
    IBV_WR_RDMA_READ            =  4,
    IBV_WR_ATOMIC_CMP_AND_SWP   =  5,
    IBV_WR_ATOMIC_FETCH_AND_ADD =  6,
    IBV_WR_LOCAL_INV            =  7,
    IBV_WR_BIND_MW              =  8,
    IBV_WR_SEND_WITH_INV        =  9,
    IBV_WR_TSO                  = 10,
    IBV_WR_DRIVER1              = 11,
    IBV_WR_RDMA_READ_RESP       = 12, // Not defined in rdma-core
    IBV_WR_RDMA_ACK             = 13, // Not defined in rdma-core
    IBV_WR_FLUSH                = 14,
    IBV_WR_ATOMIC_WRITE         = 15
} WorkReqOpCode deriving(Bits, Eq, FShow);

typedef enum {
    IBV_SEND_NO_FLAGS  = 0, // Not defined in rdma-core
    IBV_SEND_FENCE     = 1,
    IBV_SEND_SIGNALED  = 2,
    IBV_SEND_SOLICITED = 4,
    IBV_SEND_INLINE    = 8,
    IBV_SEND_IP_CSUM   = 16
} WorkReqSendFlag deriving(Bits, Eq, FShow);

instance Flags#(WorkReqSendFlag);
    function Bool isOneHotOrZero(WorkReqSendFlag inputVal) = 1 >= countOnes(pack(inputVal));
endinstance

typedef struct {
    // WorkReqID id;  // TODO: remove it
    Length len;
    ADDR laddr;
    LKEY lkey;
    QPN sqpn; // For RR dispatching
} RecvReq deriving(Bits, FShow);


// Async event related

typedef enum {
    IBV_EVENT_CQ_ERR,
    IBV_EVENT_QP_FATAL,
    IBV_EVENT_QP_REQ_ERR,
    IBV_EVENT_QP_ACCESS_ERR,
    IBV_EVENT_COMM_EST,
    IBV_EVENT_SQ_DRAINED,
    IBV_EVENT_PATH_MIG,
    IBV_EVENT_PATH_MIG_ERR,
    IBV_EVENT_DEVICE_FATAL,
    IBV_EVENT_PORT_ACTIVE,
    IBV_EVENT_PORT_ERR,
    IBV_EVENT_LID_CHANGE,
    IBV_EVENT_PKEY_CHANGE,
    IBV_EVENT_SM_CHANGE,
    IBV_EVENT_SRQ_ERR,
    IBV_EVENT_SRQ_LIMIT_REACHED,
    IBV_EVENT_QP_LAST_WQE_REACHED,
    IBV_EVENT_CLIENT_REREGISTER,
    IBV_EVENT_GID_CHANGE,
    IBV_EVENT_WQ_FATAL
} AsyncEventType deriving(Bits, Eq);


// PD Related
typedef TLog#(MAX_PD) PD_INDEX_WIDTH;
typedef TSub#(PD_HANDLE_WIDTH, PD_INDEX_WIDTH) PD_KEY_WIDTH;

typedef Bit#(PD_KEY_WIDTH)    KeyPD;
typedef UInt#(PD_INDEX_WIDTH) IndexPD;

// MR related
typedef UInt#(MR_INDEX_WIDTH) IndexMR;
typedef Bit#(MR_KEY_PART_WIDTH) KeyPartMR;


// QP Context Related

typedef 8 QPC_QUERY_RESP_MAX_DELAY;

typedef struct {
    QPN  qpn;
} ReadReqQPC deriving(Bits, Eq, FShow);

typedef struct {
    QPN  qpn;
    Maybe#(EntryQPC)  ent;
} WriteReqQPC deriving(Bits, Eq, FShow);

typedef struct {
    KeyQP                           qpnKeyPart;         // TSub#(QPN_WIDTH, QP_INDEX_WIDTH) bits = 24-11 = 13 bits
    HandlerPD                       pdHandler;          // 24 bits
    TypeQP                          qpType;             // 4 bits
    FlagsType#(MemAccessTypeFlag)   rqAccessFlags;      // 8 bits
    PMTU                            pmtu;               // 3 bits
    QPN                             peerQPN;            // 24 bits
} EntryQPC deriving(Bits, Eq, FShow);


// typedef struct {
//     RdmaPktMetaData                 metadata;
//     EntryQPC                  qpc;
// } RdmaPktMetaDataAndQPC deriving(Bits, FShow);

// typedef struct {
//     QPN  qpn;
// } ReadReqRqQPC;

// typedef struct {
//     QPN  qpn;
//     EntryRqQPC ent;
// } WriteReqRqQPC;

// typedef struct {

// } EntryRqQpc;


typedef struct {
    // Fields from BTH  // total 60 bits
    TransType trans;    // 3
    RdmaOpCode opcode;  // 5
    Bool solicited;     // 1
    QPN dqpn;           // 24
    Bool ackReq;        // 1
    PSN psn;            // 24
    PAD padCnt;         // 2

    // Fields from RETH // total 128 bits
    ADDR va;            // 64
    RKEY rkey;          // 32
    Length dlen;        // 32

    // Fields from Secondary RETH    // total 96 bits
    ADDR secondaryVa;                // 64
    RKEY secondaryRkey;              // 32

    // Fields from AETH    // total 96 bits
    AethCode                code;         // 2
    AethValue               value;        // 5
    MSN                     msn;          // 24
    PSN                     lastRetryPSN; // 24

    // Fields from ImmDT   // total 32 bits
    IMM                     immDt;        // 32

    // Fields generated by RQ logic  // total 8 bits
    RdmaReqStatus           reqStatus;    // 8 

    // Ack related                   // total 25 bits
    PSN                     expectedPsn;  // 24
    Bool                    canAutoAck;   // 1
    
} C2hReportEntry deriving(Bits);

typedef enum {
    RDMA_REQ_ST_NORMAL              = 1,
    RDMA_REQ_ST_INV_ACC_FLAG        = 2,
    RDMA_REQ_ST_INV_OPCODE          = 3,
    RDMA_REQ_ST_INV_MR_KEY          = 4,
    RDMA_REQ_ST_INV_MR_REGION       = 5,
    RDMA_REQ_ST_UNKNOWN             = 6,
    RDMA_REQ_ST_INV_HEADER          = 7,
    RDMA_REQ_ST_MAX_GUARD           = 255
} RdmaReqStatus deriving(Bits, Eq, FShow);


// Received payload stream related

typedef 9 INPUT_STREAM_FRAG_BUFFER_INDEX_WITHOUT_GUARD_WIDTH;
// typedef Bit#(INPUT_STREAM_FRAG_BUFFER_INDEX_WITHOUT_GUARD_WIDTH) InputStreamFragBufferIdxWithoutGuard; 

typedef TAdd#(1, INPUT_STREAM_FRAG_BUFFER_INDEX_WITHOUT_GUARD_WIDTH) INPUT_STREAM_FRAG_BUFFER_INDEX_WIDTH;
typedef Bit#(INPUT_STREAM_FRAG_BUFFER_INDEX_WIDTH) InputStreamFragBufferIdx; 

typedef struct {
    ByteEnBitNum                byteNum;
    Bool                        isFirst;
    Bool                        isLast;
    Bool                        isEmpty;
    InputStreamFragBufferIdx    bufIdx;
} DataStreamFragMetaData deriving(Bits, FShow);

typedef PipeOut#(DataStreamFragMetaData) DataStreamFragMetaPipeOut;
typedef Put#(DataStreamFragMetaData) DataStreamFragMetaPipeIn;

typedef 9 RAW_PACKET_RECV_BUFFER_INDEX_WIDTH;    // 512 Slots
typedef Bit#(RAW_PACKET_RECV_BUFFER_INDEX_WIDTH) RawPacketRecvBufIndex;

typedef struct {
    ADDR writeBaseAddr;
    RKEY writeMrKey;
} RawPacketReceiveMeta deriving(Bits, FShow);

typedef 4 FORCE_REPORT_HEADER_META_INTERVAL_MASK_WIDTH;

typedef struct {
    PSN  expectedPSN;
    PSN  latestErrorPSN;
    Bool isQpPsnContinous;
} ExpectedPsnContextEntry deriving(Bits, FShow);

typedef struct {
    IndexQP    qpnIdx;
    PSN        newIncomingPSN;
    Bool       isPacketStateAbnormal;
} ExpectedPsnCheckReq deriving(Bits, FShow);


typedef struct {
    PSN        expectedPSN;
    Bool       isQpPsnContinous;
    Bool       isAdjacentPsnContinous;
} ExpectedPsnCheckResp deriving(Bits, FShow);

typedef 6 RECV_PACKET_SRC_MAC_IP_BUFFER_INDEX_WIDTH;
typedef Bit#(RECV_PACKET_SRC_MAC_IP_BUFFER_INDEX_WIDTH) RecvPacketSrcMacIpBufferIdx; 

typedef struct {
    IpAddr ip;
    EthMacAddr macAddr;
} RecvPacketSrcMacIpBufferEntry deriving(Bits, FShow);

typedef struct {
    RecvPacketSrcMacIpBufferIdx srcMacIpIdx;
    PKEY pkey;
    PSN expectedPsn;
    QPN qpn;
} AutoAckGenMetaData deriving(Bits, FShow);

