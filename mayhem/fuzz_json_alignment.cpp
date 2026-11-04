// Fuzzes vg's protobuf JSON reader on vg::Alignment and the path/alignment helpers applied to what it yields.
#include <cstddef>
#include <cstdint>
#include <string>

#include <vg/io/json2pb.h>
#include <vg/vg.pb.h>

#include "alignment.hpp"
#include "path.hpp"

static volatile size_t sink;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size == 0 || size > (1 << 16)) {
        return -1;
    }
    vg::Alignment aln;
    try {
        json2pb(aln, reinterpret_cast<const char*>(data), size);
    } catch (const std::exception&) {
        return -1;
    }

    try {
        vg::Path simple = vg::simplify(aln.path());
        size_t acc = vg::path_to_length(simple) + vg::path_from_length(simple);
        acc += vg::alignment_to_length(aln) + vg::alignment_from_length(aln);
        acc += vg::cigar_string(vg::graph_cigar(aln)).size();
        acc += pb2json(aln).size();
        sink = acc;
    } catch (const std::exception&) {
        return -1;
    }
    return 0;
}
