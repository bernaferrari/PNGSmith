#ifndef PNGSMITH_CORE_H
#define PNGSMITH_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

char *pngsmith_execute_json(const char *request);
void pngsmith_string_free(char *pointer);

#ifdef __cplusplus
}
#endif

#endif

