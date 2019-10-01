#!/usr/bin/env python2
#
# Copyright 2017-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
from IPython.core.debugger import Tracer
import argparse
import json
import os
import sys
import threading

sys.path.append("utils")
import bmv2
import helper
from convert import *

#Jiachen Wang
#49678282

def ProgramSwitch(sw, id, p4info_helper):
    # DONE: Learning implementation goes here
    
    digest_name = "ethlearn_digest_t"
    digest_entry = p4info_helper.buildDigestConfig(digest_name)
    # declare two sets to keep track of the mac address and source port
    mac_address_set = set()
    source_port_set = set()
    while True:
        # Use GetDigest to get digest information, and extract source macaddress
        # and source port from it.
        response = sw.GetDigest(digest_entry)
        source_macaddress = decodeMac(response.digest.data[0].struct.members[0].bitstring)
        source_port = decodeNum(response.digest.data[0].struct.members[1].bitstring)
        
        print("source_port is", source_port)
        print("source mac address is", source_macaddress)

        # Create contents for the forwarding table.
        # when there is a match, do aiForward action, and send the packet to
        # associated egress port.  
               
        forwardTable_entry = p4info_helper.buildTableEntry(
            table_name = "cis553Ingress.tiForward",
            match_fields = {
                "hdr.ethernet.dstAddr":source_macaddress
            },
            action_name = "cis553Ingress.aiForward",
            action_params = {"egress_port" : source_port}) 

        if source_macaddress not in mac_address_set:
            sw.WriteTableEntry(forwardTable_entry)
            mac_address_set.add(source_macaddress)
        else:
            sw.UpdateTableEntry(forwardTable_entry)
        print("forward Table entry is", forwardTable_entry)
  
        # Create multicast rules. And make sure the rules are created only once.

        mcast_group_id = source_port
        if (source_port ==1) and (source_port not in source_port_set) :
            member_ports = [2,3]
            multicast_entry = p4info_helper.buildMulticastEntry(mcast_group_id,member_ports)
            sw.AddMulticastGroup(multicast_entry)
            source_port_set.add(source_port)
        elif (source_port ==2) and (source_port not in source_port_set):
            member_ports= [1,3]
            multicast_entry = p4info_helper.buildMulticastEntry(mcast_group_id,member_ports)
            sw.AddMulticastGroup(multicast_entry)
            source_port_set.add(source_port)

        elif (source_port ==3) and (source_port not in source_port_set):
            member_ports= [1,2]
            multicast_entry = p4info_helper.buildMulticastEntry(mcast_group_id,member_ports)
            sw.AddMulticastGroup(multicast_entry)
            source_port_set.add(source_port)


    sw.shutdown()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='CIS553 P4Runtime Controller')

    parser.add_argument("-b", '--bmv2-json',
                        help="path to BMv2 switch description (json)",
                        type=str, action="store", default="build/basic.json")
    parser.add_argument("-c", '--p4info-file',
                        help="path to P4Runtime protobuf description (text)",
                        type=str, action="store", default="build/basic.p4info")

    args = parser.parse_args()

    if not os.path.exists(args.p4info_file):
        parser.error("File %s does not exist!" % args.p4info_file)
    if not os.path.exists(args.bmv2_json):
        parser.error("File %s does not exist!" % args.bmv2_json)
    p4info_helper = helper.P4InfoHelper(args.p4info_file)


    threads = []

    print ("Connecting to P4Runtime server on s1...")
    sw1 = bmv2.Bmv2SwitchConnection('s1', "127.0.0.1:50051", 0)
    sw1.MasterArbitrationUpdate()
    sw1.SetForwardingPipelineConfig(p4info = p4info_helper.p4info,
                                    bmv2_json_file_path = args.bmv2_json)
    t = threading.Thread(target=ProgramSwitch, args=(sw1, 1, p4info_helper))
    t.start()
    threads.append(t)

    print ("Connecting to P4Runtime server on s2...")
    sw2 = bmv2.Bmv2SwitchConnection('s2', "127.0.0.1:50052", 1)
    sw2.MasterArbitrationUpdate()
    sw2.SetForwardingPipelineConfig(p4info = p4info_helper.p4info,
                                    bmv2_json_file_path = args.bmv2_json)
    t = threading.Thread(target=ProgramSwitch, args=(sw2, 2, p4info_helper))
    t.start()
    threads.append(t)

    print "Connecting to P4Runtime server on s3..."
    sw3 = bmv2.Bmv2SwitchConnection('s3', "127.0.0.1:50053", 2)
    sw3.MasterArbitrationUpdate()
    sw3.SetForwardingPipelineConfig(p4info = p4info_helper.p4info,
                                    bmv2_json_file_path = args.bmv2_json)
    t = threading.Thread(target=ProgramSwitch, args=(sw3, 3, p4info_helper))
    t.start()
    threads.append(t)

    for t in threads:
        t.join()