import GetPut :: *;
import ConnectableF :: *;
import PrimUtils :: *;
import DtldStream :: *;
import BasicDataTypes :: *;


typedef DtldStreamData#(DATA) DataStream;

// DATA and ByteEn are left aligned
typedef struct {
    DATA data;
    ByteEn byteEn;
    Bool isFirst;
    Bool isLast;
} DataStreamEn deriving(Bits, FShow);

typedef PipeOut#(DataStream) DataStreamPipeOut;
typedef Put#(DataStream) DataStreamPipeIn;

function DataStream reverseStream(DataStream st);
    st.data = swapEndianByte(st.data);
    return st;
endfunction

function DataStreamEn reverseStreamEnAndData(DataStreamEn st);
    st.data = swapEndianByte(st.data);
    st.byteEn = swapEndianBit(st.byteEn);
    return st;
endfunction

function DataStreamEn reverseStreamEnOnly(DataStreamEn st);
    st.byteEn = swapEndianBit(st.byteEn);
    return st;
endfunction