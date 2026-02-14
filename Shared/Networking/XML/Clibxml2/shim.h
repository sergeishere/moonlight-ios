#ifndef CLibxml2
#define CLibxml2

#import <libxml2/libxml/parser.h>

// Wrapper for xmlFree to avoid Swift 6 concurrency warnings
// (xmlFree is a mutable global function pointer in libxml2)
static inline void xmlSafeFree(void * _Nullable ptr) {
    if (ptr != NULL) {
        xmlFree(ptr);
    }
}

#endif /* CLibxml2 */
