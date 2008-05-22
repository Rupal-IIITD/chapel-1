#include "alist.h"
#include "astutil.h"
#include "baseAST.h"
#include "expr.h"
#include "passes.h"
#include "stmt.h"

static ClassType* isInnerClass(BaseAST* ast) {
  ClassType *outer = NULL, *inner = NULL;
  
  if (DefExpr* def = toDefExpr(ast)) {
    if (ClassType* ct = toClassType(def->sym->type)) {
      outer = 
        toClassType(ct->symbol->defPoint->parentSymbol->type);
      if (outer) {
        inner = ct;
      }
    }
  }

  return inner;
}

void flattenClasses(void) {

  Vec<ClassType*> all_nested_classes;
  forv_Vec(BaseAST, ast, gAsts) {
    if (ClassType* inner = isInnerClass(ast)) {
      all_nested_classes.add_exclusive(inner);
    }
  }

  // move nested classes to module level
  forv_Vec(ClassType, ct, all_nested_classes) {
    ModuleSymbol* mod = ct->getModule();
    DefExpr *def = ct->symbol->defPoint;
    def->remove();
    mod->block->insertAtTail(def);
  }
}
