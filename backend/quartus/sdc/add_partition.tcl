set_instance_assignment -name PARTITION mkBsvTopWithoutHardIpInstance -to bsv_top|bsvTopWithoutHardIpInstance -entity bluerdma_top
set_instance_assignment -name PARTITION_COLOUR 4289200038 -to bsv_top|bsvTopWithoutHardIpInstance -entity bluerdma_top
set_instance_assignment -name PARTITION mkRqGroup -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|rqGroup -entity bluerdma_top
set_instance_assignment -name PARTITION_COLOUR 4288538623 -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|rqGroup -entity bluerdma_top
set_instance_assignment -name PARTITION mkSqGroup -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|sqGroup -entity bluerdma_top
set_instance_assignment -name PARTITION_COLOUR 4285988667 -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|sqGroup -entity bluerdma_top
set_instance_assignment -name PARTITION_COLOUR 4286119859 -to bluerdma_top -entity bluerdma_top
set_instance_assignment -name PARTITION_COLOUR 4293365759 -to auto_fab_0 -entity bluerdma_top
set_instance_assignment -name PLACE_REGION "X177 Y53 X354 Y137" -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|sqGroup
set_instance_assignment -name RESERVE_PLACE_REGION OFF -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|sqGroup
set_instance_assignment -name CORE_ONLY_PLACE_REGION ON -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|sqGroup
set_instance_assignment -name REGION_NAME sqGroup -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|sqGroup
set_instance_assignment -name PLACE_REGION "X178 Y166 X351 Y268" -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|rqGroup
set_instance_assignment -name RESERVE_PLACE_REGION OFF -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|rqGroup
set_instance_assignment -name CORE_ONLY_PLACE_REGION ON -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|rqGroup
set_instance_assignment -name REGION_NAME rqGroup -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|rqGroup
set_instance_assignment -name PARTITION mkBsvTopOnlyHardIp -to bsv_top|bsvTopOnlyHardIp -entity bluerdma_top
set_instance_assignment -name PARTITION_COLOUR 4294937042 -to bsv_top|bsvTopOnlyHardIp -entity bluerdma_top
set_instance_assignment -name PLACE_REGION "X0 Y53 X162 Y261" -to bsv_top|bsvTopOnlyHardIp
set_instance_assignment -name RESERVE_PLACE_REGION OFF -to bsv_top|bsvTopOnlyHardIp
set_instance_assignment -name CORE_ONLY_PLACE_REGION ON -to bsv_top|bsvTopOnlyHardIp
set_instance_assignment -name REGION_NAME bsvTopOnlyHardIp -to bsv_top|bsvTopOnlyHardIp
set_instance_assignment -name DUPLICATE_HIERARCHY_DEPTH 5 -to rtile_reset_output_buffer_inst|reset_n_reg7
set_instance_assignment -name PRESERVE final -to bsv_top|bsvTopWithoutHardIpInstance -entity bluerdma_top
set_instance_assignment -name PRESERVE final -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|rqGroup -entity bluerdma_top
set_instance_assignment -name PRESERVE final -to bsv_top|bsvTopOnlyHardIp -entity bluerdma_top
set_instance_assignment -name PRESERVE final -to bsv_top|bsvTopWithoutHardIpInstance|qpMrPgtQpc|sqGroup -entity bluerdma_top