import Reserved :: *;

import RdmaHeaders :: *;
import DataTypes :: *;
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
    Bit#(7)                 opCode;         //  7  bits
    ReservedZero#(7)        reserved0;      //  7  bits
    Bool                    hasNextFrag;    //  1  bits
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

    PKEY                        pkey;             // 16 bits
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


    ReservedZero#(3)            reserved0;          // 3  bits
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
    ReservedZero#(64)               reserved3;              // 64  bits
    ReservedZero#(21)               reserved2;              // 16  bits
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
    ReservedZero#(64)               reserved3;              // 136 bits
    ReservedZero#(64)               reserved2;              // 136 bits
    ReservedZero#(8)                reserved1;              // 136 bits
    QPN                             qpn;                    // 24  bits
    ReservedZero#(8)                reserved0;              // 8   bits
    PSN                             recoverPoint;           // 24  bits
    RingbufDescCmdQueueCommonHead   cmdQueueCommonHeader;   // 48  bits
    RingbufDescCommonHead           commonHeader;           // 16  bits
} CmdQueueReqDescUpdateErrorPsnRecoverPoint deriving(Bits, FShow);