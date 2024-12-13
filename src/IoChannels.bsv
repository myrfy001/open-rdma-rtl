import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import BasicDataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import FTileMacAdaptor :: *;
import RTilePcieAdaptor :: *;
import DtldStream :: *;

typedef PCIE_MPS IO_CHANNEL_PCIE_MAX_REQ_LENGTH_IN_BYTE;


typedef DtldStreamMemAccessMeta#(ADDR, Length) IoChannelMemoryAccessMeta;
typedef DtldStreamData#(DATA) IoChannelMemoryAccessDataStream;

typedef DtldStreamMasterReadPipes#(DATA, ADDR, Length) IoChannelMemoryReadMasterPipe;
typedef DtldStreamMasterWritePipes#(DATA, ADDR, Length) IoChannelMemoryWriteMasterPipe;
typedef DtldStreamSlaveReadPipes#(DATA, ADDR, Length) IoChannelMemoryReadSlavePipe;
typedef DtldStreamSlaveWritePipes#(DATA, ADDR, Length) IoChannelMemoryWriteSlavePipe;

typedef DtldStreamBiDirMasterPipes#(DATA, ADDR, Length) IoChannelMemoryMasterPipe;
typedef DtldStreamBiDirSlavePipes#(DATA, ADDR, Length) IoChannelMemorySlavePipe;