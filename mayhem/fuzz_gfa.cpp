// Fuzzes vg's GFA reader (gfa_to_path_handle_graph) and the GFA writer on whatever graph came out.
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>

#include <bdsg/hash_graph.hpp>

#include "algorithms/gfa_to_handle.hpp"
#include "gfa.hpp"

static volatile size_t sink;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size == 0 || size > (1 << 16)) {
        return -1;
    }
    std::istringstream in(std::string(reinterpret_cast<const char*>(data), size));
    bdsg::HashGraph graph;
    try {
        vg::algorithms::gfa_to_path_handle_graph(in, &graph);
    } catch (const std::exception&) {
        return -1;
    }

    size_t bases = 0;
    graph.for_each_handle([&](const handlegraph::handle_t& h) {
        bases += graph.get_length(h);
        graph.follow_edges(h, false, [&](const handlegraph::handle_t&) { return true; });
        graph.follow_edges(h, true, [&](const handlegraph::handle_t&) { return true; });
    });
    graph.for_each_path_handle([&](const handlegraph::path_handle_t& p) {
        graph.for_each_step_in_path(p, [&](const handlegraph::step_handle_t& s) {
            graph.get_sequence(graph.get_handle_of_step(s));
        });
    });

    std::ostringstream out;
    try {
        vg::graph_to_gfa(&graph, out);
    } catch (const std::exception&) {
        return -1;
    }
    sink = bases + out.str().size();
    return 0;
}
