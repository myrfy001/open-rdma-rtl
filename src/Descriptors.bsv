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
    ReservedZero#(7)        reserved1;      //  7  bits
    Bool                    hasNextFrag;    //  1  bits
} RingbufDescCommonHead deriving(Bits, FShow);


typedef struct {
    QPN                         dqpn;             // 24 bits
    PSN                         psn;              // 24 bits

    PKEY                        pkey;             // 16 bits
    IpAddr                      dqpIP;            // 32 bits
    RKEY                        rkey;             // 32 bits
    ADDR                        raddr;            // 64 bits
    Length                      totalLen;         // 32 bits

    ReservedZero#(3)            reserved2;        // 3  bits
    WorkReqSendFlag             flags;            // 5  bits 

    ReservedZero#(4)            reserved3;        // 4  bits
    TypeQP                      qpType;           // 4  bits

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


    ReservedZero#(3)            reserved8;          // 3  bits
    Bool                        isLast;             // 1  bits
    Bool                        isFirst;            // 1  bits
    PMTU                        pmtu;               // 3  bits

    RingbufDescCommonHead       commonHeader;       // 16 bits
} SendQueueReqDescSeg1 deriving(Bits, FShow);




typedef struct {
    ReservedZero#(240)              reserved1;      // 240 bits
    RingbufDescCommonHead           commonHeader;   // 16  bits
} CmdQueueRespDescOnlyCommonHeader deriving(Bits, FShow);

typedef struct {
    ReservedZero#(7)            reserved1;
    Bit#(17)                    pgtOffset;
    Bit#(8)                     accFlags;
    Bit#(32)                    pdHandler;
    Bit#(32)                    mrKey;
    Bit#(32)                    mrLength;
    Bit#(64)                    mrBaseVA;
    ReservedZero#(32)           reserved2;      // 32  bits
    Bit#(16)                    userData;       // 16  bits
    RingbufDescCommonHead       commonHeader;   // 16  bits
} CmdQueueReqDescUpdateMrTable deriving(Bits, FShow);

typedef struct {
    ReservedZero#(64)           reserved1;
    Bit#(32)                    zeroBasedEntryCount;
    Bit#(32)                    startIndex;
    Bit#(64)                    dmaAddr;
    ReservedZero#(32)           reserved2;      // 32  bits
    Bit#(16)                    userData;       // 16  bits
    RingbufDescCommonHead       commonHeader;   // 16  bits
} CmdQueueReqDescUpdatePGT deriving(Bits, FShow);

typedef struct {
    ReservedZero#(64)           reserved1;
    ReservedZero#(64)           reserved2;
    ReservedZero#(64)           reserved3;
    ReservedZero#(32)           reserved4;      // 32  bits
    Bit#(16)                    userData;       // 16  bits
    RingbufDescCommonHead       commonHeader;   // 16  bits
} CmdQueueRespDescUpdatePGT deriving(Bits, FShow);


typedef struct {
    ReservedZero#(80 )              reserved1;      // 80  bits
    QPN                             peerQPN;        // 24  bits
    ReservedZero#(5)                reserved2;      // 5   bits
    PMTU                            pmtu;           // 3   bits
    FlagsType#(MemAccessTypeFlag)   rqAccessFlags;  // 8   bits
    ReservedZero#(4)                reserved3;      // 4   bits
    TypeQP                          qpType;         // 4   bits
    HandlerPD                       pdHandler;      // 32  bits
    QPN                             qpn;            // 24  bits
    ReservedZero#(6)                reserved4;      // 6   bits
    Bool                            isError;        // 1   bit
    Bool                            isValid;        // 1   bit
    ReservedZero#(32)               reserved5;      // 32  bits
    Bit#(16)                        userData;       // 16  bits
    RingbufDescCommonHead           commonHeader;   // 16  bits
} CmdQueueReqDescQpManagementSeg0 deriving(Bits, FShow);


typedef CmdQueueReqDescQpManagementSeg0 CmdQueueRespDescQpManagementSeg0;


typedef struct {
    ReservedZero#(16)           reserved1;      // 16  bits
    EthMacAddr                  macAddr;        // 48  bits
    ReservedZero#(32)           reserved2;      // 32  bits
    IpAddr                      ipAddr;         // 32  bits
    IpNetMask                   netMask;        // 32  bits
    IpGateWay                   gateWay;        // 32  bits
    ReservedZero#(32)           reserved3;      // 32  bits
    Bit#(16)                    userData;       // 16  bits
    RingbufDescCommonHead       commonHeader;   // 16  bits
} CmdQueueReqDescSetNetworkParam deriving(Bits, FShow);


typedef struct {
    ReservedZero#(96)           reserved1;      // 96  bits
    RKEY                        writeMrKey;     // 32  bits
    ADDR                        writeBaseAddr;  // 64  bits
    ReservedZero#(32)           reserved2;      // 32  bits
    Bit#(16)                    userData;       // 16  bits
    RingbufDescCommonHead       commonHeader;   // 16  bits
} CmdQueueReqDescSetRawPacketReceiveMeta deriving(Bits, FShow);

typedef struct {
    ReservedZero#(136)          reserved1;      // 136 bits
    QPN                         qpn;            // 24  bits
    ReservedZero#(8)            reserved2;      // 8   bits
    PSN                         recoverPoint;   // 24  bits
    ReservedZero#(32)           reserved3;      // 32  bits
    Bit#(16)                    userData;       // 16  bits
    RingbufDescCommonHead       commonHeader;   // 16  bits
} CmdQueueReqDescUpdateErrorPsnRecoverPoint deriving(Bits, FShow);