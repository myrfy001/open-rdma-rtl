import Reserved :: *;

import RdmaHeaders :: *;
import BasicDataTypes :: *;
import EthernetTypes :: *;


typedef enum {
    CmdQueueOpcodeUpdateMrTable = 'h0,
    CmdQueueOpcodeUpdatePGT = 'h1,
    CmdQueueOpcodeQpManagement = 'h2,
    CmdQueueOpcodeSetNetworkParam = 'h3,
    CmdQueueOpcodeSetRawPacketReceiveMeta = 'h4,
    CmdQueueOpcodeUpdateErrorPsnRecoverPoint = 'h5
} CommandQueueOpcode deriving(Bits, Eq);

typedef struct {
    Bool                    valid;          //  1  bits
    Bool                    hasNextFrag;    //  1  bits
    ReservedZero#(5)        reserved0;      //  7  bits
    Bool                    isExtendOpcode; //  1  bits  Reserved for extension. For MetaReport queue, if this is false, opcode is equal to RDMA's opcode, otherwise, the opcode has different meaning.
    Bit#(8)                 opCode;         //  8  bits
} RingbufDescCommonHead deriving(Bits, FShow);


typedef struct {
    ReservedZero#(3)            reserved1;        // 3  bits
    WorkReqSendFlag             flags;            // 5  bits 
    QPN                         dqpn;             // 24 bits
    ReservedZero#(4)            reserved0;        // 4  bits
    TypeQP                      qpType;           // 4  bits
    PSN                         psn;              // 24 bits

    IpAddr                      dqpIP;            // 32 bits
    ADDR                        raddr;            // 64 bits
    RKEY                        rkey;             // 32 bits
    Length                      totalLen;         // 32 bits

    MSN                         msn;              // 16 bits
    RingbufDescCommonHead       commonHeader;     // 16 bits
} SendQueueReqDescSeg0 deriving(Bits, FShow);


typedef struct {
    ADDR                        laddr;              // 64 bits
    Length                      len;                // 32 bits
    LKEY                        lkey;               // 32 bits
    
    Bit#(16)                    sqpnHigh16Bits;     // 16 bits
    EthMacAddr                  macAddr;            // 48 bits

    IMM                         imm;                // 32 bits

    Bit#(8)                     sqpnLow8Bits;       // 8  bits


    ReservedZero#(2)            reserved0;          // 2  bits
    Bool                        isRetry;            // 1  bits  tell the receiver whether this a retry packet. if it is, then always report to receiver's software since the reorder bitmap can handle this packet.
    Bool                        isLast;             // 1  bits
    Bool                        isFirst;            // 1  bits
    PMTU                        pmtu;               // 3  bits

    RingbufDescCommonHead       commonHeader;       // 16 bits
} SendQueueReqDescSeg1 deriving(Bits, FShow);



typedef struct {
    ReservedZero#(31)       reserved0;      // 31  bits
    Bool                    isSuccess;      //  1  bits
    Bit#(16)                userData;       // 16  bits
} RingbufDescCmdQueueCommonHead deriving(Bits, FShow);


typedef struct {
    ReservedZero#(64)               reserved2;              // 64  bits
    ReservedZero#(64)               reserved1;              // 64  bits
    ReservedZero#(64)               reserved0;              // 64  bits
    RingbufDescCmdQueueCommonHead   cmdQueueCommonHeader;   // 48  bits
    RingbufDescCommonHead           commonHeader;           // 16  bits
} CmdQueueRespDescOnlyCommonHeader deriving(Bits, FShow);

typedef struct {
    ReservedZero#(7)                reserved1;
    Bit#(17)                        pgtOffset;
    Bit#(8)                         accFlags;
    Bit#(32)                        pdHandler;
    Bit#(32)                        mrKey;
    Bit#(32)                        mrLength;
    Bit#(64)                        mrBaseVA;
    RingbufDescCmdQueueCommonHead   cmdQueueCommonHeader;   // 48  bits
    RingbufDescCommonHead           commonHeader;           // 16  bits
} CmdQueueReqDescUpdateMrTable deriving(Bits, FShow);

typedef struct {
    ReservedZero#(64)               reserved0;
    Bit#(32)                        zeroBasedEntryCount;
    Bit#(32)                        startIndex;
    Bit#(64)                        dmaAddr;
    RingbufDescCmdQueueCommonHead   cmdQueueCommonHeader;   // 48  bits
    RingbufDescCommonHead           commonHeader;           // 16  bits
} CmdQueueReqDescUpdatePGT deriving(Bits, FShow);

typedef struct {
    EthMacAddr                      peerMacAddr;            // 48  bits
    Word                            peerIpAddrLow;          // 16  bits
    Word                            peerIpAddrHigh;         // 16  bits
    ReservedZero#(5)                reserved2;              // 5   bits
    PMTU                            pmtu;                   // 3   bits
    ReservedZero#(4)                reserved1;              // 4   bits
    TypeQP                          qpType;                 // 4   bits
    FlagsType#(MemAccessTypeFlag)   rqAccessFlags;          // 8   bits
    QPN                             peerQPN;                // 24  bits
    HandlerPD                       pdHandler;              // 32  bits
    QPN                             qpn;                    // 24  bits
    ReservedZero#(6)                reserved0;              // 6   bits
    Bool                            isError;                // 1   bit
    Bool                            isValid;                // 1   bit
    RingbufDescCmdQueueCommonHead   cmdQueueCommonHeader;   // 48  bits
    RingbufDescCommonHead           commonHeader;           // 16  bits
} CmdQueueReqDescQpManagement deriving(Bits, FShow);


typedef CmdQueueReqDescQpManagement CmdQueueRespDescQpManagement;


typedef struct {
    ReservedZero#(16)               reserved1;              // 16  bits
    EthMacAddr                      macAddr;                // 48  bits
    ReservedZero#(32)               reserved0;              // 32  bits
    IpAddr                          ipAddr;                 // 32  bits
    IpNetMask                       netMask;                // 32  bits
    IpGateWay                       gateWay;                // 32  bits
    RingbufDescCmdQueueCommonHead   cmdQueueCommonHeader;   // 48  bits
    RingbufDescCommonHead           commonHeader;           // 16  bits
} CmdQueueReqDescSetNetworkParam deriving(Bits, FShow);


typedef struct {
    ReservedZero#(64)               reserved1;              // 64  bits
    ReservedZero#(64)               reserved0;              // 64  bits
    ADDR                            writeBaseAddr;          // 64  bits
    RingbufDescCmdQueueCommonHead   cmdQueueCommonHeader;   // 48  bits
    RingbufDescCommonHead           commonHeader;           // 16  bits
} CmdQueueReqDescSetRawPacketReceiveMeta deriving(Bits, FShow);


typedef struct {
    ImmDt                       immData;          // 32 bits
    // the following is RETH related fields
    RKEY                        rkey;             // 32 bits
    ADDR                        raddr;            // 64 bits
    Length                      totalLen;         // 32 bits

    
    // the following is BTH related fields
    ReservedZero#(8)            reserved1;        // 8  bits
    QPN                         dqpn;             // 24 bits

    ReservedZero#(5)            reserved0;        // 5  bits
    Bool                        ackReq;           // 1  bits
    Bool                        solicited;        // 1  bits
    Bool                        ecnMarked;        // 1  bits
    PSN                         psn;              // 24 bits

    MSN                         msn;              // 16 bits
    RingbufDescCommonHead       commonHeader;     // 16 bits
} MetaReportQueuePacketBasicInfoDesc deriving(Bits, FShow);

typedef struct {
    ReservedZero#(96)           reserved1;        // 96 bits
    // the following is RETH related fields, mainly used for Read Req.
    LKEY                        lkey;             // 32 bits
    ADDR                        laddr;            // 64 bits
    Length                      totalLen;         // 32 bits

    ReservedZero#(16)           reserved0;        // 16 bits
    RingbufDescCommonHead       commonHeader;     // 16 bits
} MetaReportQueueReadReqExtendInfoDesc deriving(Bits, FShow);


typedef struct {
    AckBitmap                   nowBitmap;          // 128bits

    ReservedZero#(16)           reserved4;          // 16 bits
    MSN                         msn;                // 16 bits only valid when it's received from remote, if it is generated by local, then it's meaning less.
    ReservedZero#(8)            reserved3;          // 8 Bits
    PSN                         psnNow;             // 24 bits

    ReservedZero#(8)            reserved2;          // 8 Bits
    PSN                         psnBeforeSlide;     // 24 bits

    ReservedZero#(8)            reserved1;          // 8 Bits
    Bool                        isPacketLost;       // 1 Bit 
    Bool                        isWindowSlided;     // 1 Bit
    Bool                        isSendByDriver;     // 1 Bit  indicate whether sent by driver, since software doesn't known the newest ACK's PSN on hardware. When ack is send by software, MSN is unused.
    Bool                        isSendByLocalHw;    // 1 Bit  indicate whether sent by local hardware. if True, means this ack is generated by local Hw, and the same reported content will also be sent to remote peer. if false, it means the reported content is reveiced from remote peer.
    ReservedZero#(4)            reserved0;          // 4 Bits
    RingbufDescCommonHead       commonHeader;       // 16 bits
} MetaReportQueueAckDesc deriving(Bits, FShow);

typedef struct {
    AckBitmap                   preBitmap;          // 128bits
    ReservedZero#(64)           reserved2;          // 64 Bits
    ReservedZero#(32)           reserved1;          // 32 Bits
    ReservedZero#(16)           reserved0;          // 16 Bits
    RingbufDescCommonHead       commonHeader;       // 16 bits
} MetaReportQueueAckExtraDesc deriving(Bits, FShow);