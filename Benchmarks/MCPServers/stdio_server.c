// A fake MCP server in C for MCPStress: the cheapest possible server, so what is measured is the client. It reads the id and the
// requested size with byte scans, not a JSON parser, and answers initialize and tools/call; every other request gets an empty result.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static long number_after(const char *line, const char *key) {
    const char *at = strstr(line, key);
    return at ? strtol(at + strlen(key), NULL, 10) : -1;
}

int main(void) {
    char *line = NULL, *text = NULL;
    size_t capacity = 0;
    long text_size = -1;
    setvbuf(stdout, NULL, _IOFBF, 1 << 20);
    while (getline(&line, &capacity, stdin) > 0) {
        long id = number_after(line, "\"id\":");
        if (id < 0) continue;
        if (strstr(line, "\"initialize\"")) {
            printf("{\"jsonrpc\":\"2.0\",\"id\":%ld,\"result\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{\"tools\":{}},"
                   "\"serverInfo\":{\"name\":\"fake-c\",\"version\":\"1\"}}}\n", id);
        } else if (strstr(line, "\"tools/call\"")) {
            long size = number_after(line, "\"size\":");
            if (size < 0) size = 2;
            if (size != text_size) {
                free(text);
                text = malloc(size + 1);
                memset(text, 'x', size);
                text[size] = 0;
                text_size = size;
            }
            printf("{\"jsonrpc\":\"2.0\",\"id\":%ld,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"%s\"}],\"isError\":false}}\n",
                   id, text);
        } else {
            printf("{\"jsonrpc\":\"2.0\",\"id\":%ld,\"result\":{}}\n", id);
        }
        fflush(stdout);
    }
    return 0;
}
