//Name: Jiachen Wang
//ID: 49678282

/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>


typedef bit<48> macAddr_t;
typedef bit<9>  portId_t;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

struct cis553_metadata_t {
    // Declare local variables here
}

struct headers_t {
    ethernet_t  ethernet;
}

struct ethlearn_digest_t {
    macAddr_t   srcAddr;
    portId_t    srcPort;
}

/*************************************************************************
***********************  P A R S E   P A C K E T *************************
*************************************************************************/


// Declare a parser named cis553Parser.The parser reads its input from a packet_in, named packet here,
// which is a pre-defined P4 extern object that represents an incoming packet. 
// The parser writes its output into the parsed_header argument.
// Metadata and standard_metadata are metadata, and they are both inputs and outputs.
parser cis553Parser(packet_in packet,
                    out headers_t parsed_header,
                    inout cis553_metadata_t metadata,
                    inout standard_metadata_t standard_metadata) {

    
    // The parser starts. And state gets transferred to parse_ethernet, 
    // which is defined right after this part.
    state start {
        transition parse_ethernet;
    }

    
    // Define state 'parse_ethernet'. 
    // We first extract 'ethernet' data from packet into our declared 'parsed_header.ethernet' header.
    // We then transfer the state again, 'select' statement here is used to branch in the parser.
    // In parsers it is often necessary to branch based on some of the bits just parsed, here the 'etherType'
    // Usually if there is a match pattern, we branch to some other state. 
    // But here we just accept by default, accept also indicates the success of parsing.
    state parse_ethernet {
        packet.extract(parsed_header.ethernet);
        transition select(parsed_header.ethernet.etherType) {
            default: accept;
        }
    }
}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control cis553VerifyChecksum(inout headers_t hdr,
                             inout cis553_metadata_t meta) {
     apply { }
}


/*************************************************************************
***********************  I N G R E S S  **********************************
*************************************************************************/


/* This type declaration describes a block named cis553Ingress that can be programmed
 using a data-dependent sequence of match-action unit invocations 
 and other imperative constructs (indicated by the control keyword).  
 The first parameter is an object of type headers_t named hdr, 
 where headers_t is a type variable we have defined.
 The direction inout indicates that this parameter is both an input and an output.
 Same for metadata and standard_metadata,
 they are objects of type cis553_metadata_t and standard_metadata_t, 
 and they are also both inputs and outputs. 
 'Both inputs and outputs' means that the block will receive them as inputs, 
  and update them as outputs */
control cis553Ingress(inout headers_t hdr,
                      inout cis553_metadata_t metadata,
                      inout standard_metadata_t standard_metadata) {
    
    /* Declare an action called aiForward, the parameter 'egress_port' is of type
     portId_t, which we have defined before. 
     Since this parameter does not have direction, it indicates 'action data'.
     What this action does is: update the 'egress_spec' field of 
     standard_metadata with the egress_port ID.
     'egress_spec' is the port to which the packet should be sent to. */
    action aiForward(portId_t egress_port) {
        standard_metadata.egress_spec = egress_port;
    }

    
    /* Decalre another action called aiForwardUnknown.
       It defines the behavior of packets that have not been seen before.
     */
    action aiForwardUnknown() {
        
        /* This action uses a digest to notify the control plane about 
        source Ethernet MAC addresses and ingress ports of packets 
        that have not been seen before.
        Here, 'mac_learn_digest' will be sent to control plane. */
        ethlearn_digest_t mac_learn_digest = {hdr.ethernet.srcAddr,
                                              standard_metadata.ingress_port};
        digest(0, mac_learn_digest);

        
        /* This parts does the multicasting. The 'mcast_grp' is the multicast group id. 
         The reason why we use the ingress_port as the multicast group id is because:
         when an unknown packet comes, there are no entries in the L2 MAC table for the
         destination MAC address. Typically in this case, we flood the packet to all local 
         ports, except the ingress port. Thus, using the ingress port to label the multicast group
         means that the packet sent to this group is from this ingress port,
         and also avoids unnecessary multicasting.
         */
        bit<16> MULTICAST_GROUP = (bit<16>) standard_metadata.ingress_port;
        standard_metadata.mcast_grp = MULTICAST_GROUP;
    }

    
    /* Declare a table called 'tiForward', 
     the key is 'hdr.ethernet.dstAddr', which is the destination address.
     If there is an exact match in the look-up table, do the actions in the action list.
     If there is no match, do the default_action, which is 'aiForwardUnknown()'*/
    table tiForward {
        key = {
            hdr.ethernet.dstAddr : exact;
        }
        actions = {
            aiForward;
            aiForwardUnknown;
        }

        default_action = aiForwardUnknown();
    }

    
    // Invoke the table.
    // Applying a table executes the corresponding match-action unit.
    apply {
        tiForward.apply();
    }
}


/*************************************************************************
***********************  E G R E S S  ************************************
*************************************************************************/

control cis553Egress(inout headers_t hdr,
                     inout cis553_metadata_t metadata,
                     inout standard_metadata_t standard_metadata) {
    apply { }
}


/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   ***************
*************************************************************************/

control cis553ComputeChecksum(inout headers_t hdr,
                              inout cis553_metadata_t meta) {
    // Note that the switch handles the Ethernet checksum.
    // We don't need to deal with that.
    apply { }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   ********************
*************************************************************************/

control cis553Deparser(packet_out packet, in headers_t hdr) {
    apply {
        packet.emit(hdr.ethernet);
    }
}

/*************************************************************************
***********************  S W I T C H  ************************************
*************************************************************************/

V1Switch(cis553Parser(),
         cis553VerifyChecksum(),
         cis553Ingress(),
         cis553Egress(),
         cis553ComputeChecksum(),
         cis553Deparser()) main;
