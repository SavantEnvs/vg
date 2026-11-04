// Fuzzes the serialized snarl distance index (.dist) loader, the way vg reads one from disk
// (haplotypes_main.cpp, index_registry.cpp): SnarlDistanceIndex::deserialize(filename), then a bounded
// walk of the snarl tree and a few distance queries on what loaded.
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include <unistd.h>

#include "snarl_distance_index.hpp"

static volatile size_t sink;

static void walk(const vg::SnarlDistanceIndex& index, const handlegraph::net_handle_t& parent, size_t depth,
                 size_t& budget, std::vector<handlegraph::nid_t>& ids, size_t& acc) {
    if (depth > 8) {
        return;
    }
    index.for_each_child(parent, [&](const handlegraph::net_handle_t& child) {
        if (budget == 0) {
            return false;
        }
        budget--;
        acc += index.minimum_length(child);
        if (index.is_node(child)) {
            if (ids.size() < 8) {
                ids.push_back(index.node_id(child));
            }
        } else if (index.is_chain(child) || index.is_snarl(child) || index.is_root_snarl(child)) {
            walk(index, child, depth + 1, budget, ids, acc);
        }
        return true;
    });
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size == 0 || size > (1 << 16)) {
        return -1;
    }

    const char* tmpdir = getenv("TMPDIR");
    std::string path = std::string(tmpdir && *tmpdir ? tmpdir : "/tmp") + "/fuzz_dist_XXXXXX";
    int fd = mkstemp(&path[0]);
    if (fd < 0) {
        return -1;
    }
    size_t written = 0;
    while (written < size) {
        ssize_t n = write(fd, data + written, size - written);
        if (n <= 0) {
            break;
        }
        written += static_cast<size_t>(n);
    }
    close(fd);
    if (written != size) {
        unlink(path.c_str());
        return -1;
    }

    int result = 0;
    try {
        vg::SnarlDistanceIndex index;
        index.deserialize(path);

        std::vector<handlegraph::nid_t> ids;
        size_t budget = 64, acc = 0;
        walk(index, index.get_root(), 0, budget, ids, acc);
        for (size_t i = 0; i < ids.size(); i++) {
            for (size_t j = 0; j < ids.size(); j++) {
                acc += index.minimum_distance(ids[i], false, 0, ids[j], false, 0);
            }
        }
        sink = acc;
    } catch (const std::exception&) {
        result = -1;
    }
    unlink(path.c_str());
    return result;
}
