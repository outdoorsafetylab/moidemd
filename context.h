#ifndef CONTEXT_H
#define CONTEXT_H

struct context;
context *ContextCreate(const char *, const char *);
void ContextFree(context *);
void ContextGetBounds(context *, double *t, double *l, double *b, double *r);
double ContextGetAltitude(context *, double, double);

#endif // CONTEXT_H
