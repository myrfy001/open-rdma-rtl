import EthernetFrameIO :: *;
import Connectable :: *;
import ConnectableF :: *;

(* doc = "testcase" *)
module mkTestInputPacketClassifier(Empty);
    let packetGen <- mkEthernetPacketGenerator;
    let packetCon <- mkRdmaHeaderExtractor;
    let packetClassifier <- mkInputPacketClassifier;

    mkConnection(packetGen.ethernetPacketPipeOut, packetClassifier.ethRawPacketPipeIn);

endmodule