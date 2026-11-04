// Fuzzes the snarl decomposition and distance index: parse a GFA, decompose it, build the SnarlDistanceIndex
// and query minimum/maximum distances between nodes of the result.
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

#include <bdsg/hash_graph.hpp>

#include "algorithms/gfa_to_handle.hpp"
#include "integrated_snarl_finder.hpp"
#include "snarl_distance_index.hpp"

static volatile size_t sink;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size == 0 || size > (1 << 13)) {
        return -1;
    }
    std::istringstream in(std::string(reinterpret_cast<const char*>(data), size));
    bdsg::HashGraph graph;
    try {
        vg::algorithms::gfa_to_path_handle_graph(in, &graph);
    } catch (const std::exception&) {
        return -1;
    }
    if (graph.get_node_count() == 0 || graph.get_node_count() > 256 || graph.max_node_id() > (1 << 20)) {
        return -1;
    }

    try {
        vg::IntegratedSnarlFinder finder(graph);
        vg::SnarlDistanceIndex index;
        vg::fill_in_distance_index(&index, &graph, &finder);

        std::vector<handlegraph::nid_t> ids;
        graph.for_each_handle([&](const handlegraph::handle_t& h) {
            if (ids.size() < 12) {
                ids.push_back(graph.get_id(h));
            }
            return true;
        });
        size_t acc = 0;
        for (size_t i = 0; i < ids.size(); i++) {
            for (size_t j = 0; j < ids.size(); j++) {
                acc += index.minimum_distance(ids[i], false, 0, ids[j], false, 0);
                acc += index.minimum_distance(ids[i], true, 0, ids[j], false, 0);
            }
        }
        sink = acc;
    } catch (const std::exception&) {
        return -1;
    }
    return 0;
}
