typedef Bit#(64) SimulationTime;

function Action immAssertForFpCheck(Bool condition, String assertName, Fmt assertFmtMsg);
    action
        let pos = printPosition(getStringPosition(assertName));
        // let pos = printPosition(getEvalPosition(condition));
        if (!condition) begin
            $error(
                "ImmAssert failed in %m @time=%0t: %s-- %s: ",
                $time, pos, assertName, assertFmtMsg
            );
            $finish(1);
        end
    endaction
endfunction

function Action checkFullyPipeline(SimulationTime previousBeatTime, Integer maxAllowedBeat, Integer clockPeriod, String name);
    action
        SimulationTime curTime <- $time;
        let deltaTime = (curTime - previousBeatTime) * 1000;
        SimulationTime allowedDelta = fromInteger(maxAllowedBeat * clockPeriod);
        Bool needFullyPipelineCheck <- $test$plusargs("fully-pipeline-check");
        immAssertForFpCheck(
            (!needFullyPipelineCheck) || (deltaTime <= allowedDelta),
            "checkFullyPipeline Failed",
            $format("name = %s", name, ", previousBeatTime=", fshow(previousBeatTime), ", curTime=", fshow(curTime), ", deltaTime=", fshow(deltaTime), ", allowedDelta=", fshow(allowedDelta))
        );
        // $display("checkFullyPipeline name = %s", name, ", previousBeatTime=", fshow(previousBeatTime), ", curTime=", fshow(curTime), ", deltaTime=", fshow(deltaTime), ", allowedDelta=", fshow(allowedDelta));
    endaction
endfunction