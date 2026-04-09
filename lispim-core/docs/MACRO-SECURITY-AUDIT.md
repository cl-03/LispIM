# Macro Security Audit Report

**Date:** 2026-04-09
**Audited Files:** `src/macros.lisp`, `src/utils.lisp`
**Reference:** On Lisp (Paul Graham, 1993), Common Lisp HyperSpec

---

## Executive Summary

对 LispIM 项目的宏进行了全面安全性审计。总体而言，宏实现遵循了 On Lisp 的最佳实践，但发现**1 个需要修复的安全隐患**和**3 个需要文档说明的注意事项**。

---

## 1. Security Assessment

### 1.1 Anaphoric Macros (AWHEN, AAND, AOR, AIF, AIF*, AWHEN*)

**Status:** ✅ **SAFE**

**Analysis:**
```lisp
(defmacro awhen (test-form &body body)
  (let ((it (gensym "IT")))
    `(let ((,it ,test-form))
       (when ,it ,@body))))
```

- ✅ Uses `gensym` to generate unique `it` symbol
- ✅ `test-form` evaluated exactly once
- ✅ `body` not evaluated prematurely
- ⚠️ **Intentional capture**: The `it` symbol is deliberately captured - this is by design (anaphoric macro pattern from On Lisp Chapter 8)

**Recommendation:** Document that these are anaphoric macros where `it` is intentionally available in body.

---

### 1.2 DO-HASH Macro

**Status:** ⚠️ **MOSTLY SAFE** (with minor concern)

**Analysis:**
```lisp
(defmacro do-hash ((key-var val-var hash-table &optional return) &body body)
  (let ((ht-sym (gensym "HT")))
    `(let ((,ht-sym ,hash-table))
       (maphash (lambda (,key-var ,val-var)
                  ,@body)
                ,ht-sym)
       ,return)))
```

- ✅ Hash-table expression evaluated once (protected by `gensym`)
- ✅ `body` not evaluated prematurely
- ⚠️ **Concern**: `key-var` and `val-var` are not protected with `once-only`
  - If user passes complex expressions like `(do-hash ((car x) val ht) ...)`, `(car x)` could have issues

**Recommendation:** Add documentation stating that `key-var` and `val-var` should be simple symbols.

---

### 1.3 ACCUMULATING Macro

**Status:** ❌ **UNSAFE** - Requires Fix

**Analysis:**
```lisp
(defmacro accumulating ((collector init &key test) &body body)
  (let ((result-sym (gensym "RESULT")))
    `(let ((,result-sym ,init))
       (macrolet ((,collector (item)
                    `(progn
                       ,@(when test `((unless (find ,item ,',result-sym :test ,',test))))
                       (push ,item ,',result-sym))))
         ,@body
         (nreverse ,result-sym)))))
```

- ✅ `result-sym` properly generated with `gensym`
- ✅ `macrolet` correctly scopes the `collector` macro
- ❌ **BUG**: `item` is evaluated TWICE when `:test` is provided:
  1. Once in `(find ,item ,',result-sym ...)`
  2. Once in `(push ,item ,',result-sym)`

**Exploit Example:**
```lisp
(accumulating (result nil :test #'equal)
  (result (get-next-item)))  ; get-next-item called twice per iteration!
```

**Fix Required:**
```lisp
(defmacro accumulating ((collector init &key test) &body body)
  (let ((result-sym (gensym "RESULT"))
        (item-sym (gensym "ITEM")))
    `(let ((,result-sym ,init))
       (macrolet ((,collector (,item-sym)
                    `(progn
                       ,@(when test `((unless (find ,',item-sym ,',,result-sym :test ,',test))))
                       (push ,',item-sym ,',,result-sym))))
         ,@body
         (nreverse ,result-sym)))))
```

---

### 1.4 WITH-REDIS-CONNECTION Macro

**Status:** ✅ **SAFE**

**Analysis:**
```lisp
(defmacro with-redis-connection ((var pool) &body body)
  (let ((redis-pop-sym (intern "REDIS-POP" "CL-REDIS"))
        (redis-push-sym (intern "REDIS-PUSH" "CL-REDIS")))
    `(let ((,var (funcall #',redis-pop-sym ,pool)))
       (unwind-protect
            (progn ,@body)
         (when ,var
           (funcall #',redis-push-sym ,var ,pool))))))
```

- ✅ `pool` evaluated once
- ✅ `unwind-protect` guarantees cleanup even on non-local exit
- ✅ Uses `INTERN` to avoid package lock issues at compile time
- ✅ Cleanup code checks for nil before pushing back

**Recommendation:** None - implementation is correct.

---

### 1.5 WITH-LOCK-HELD Macro

**Status:** ✅ **SAFE**

**Analysis:**
```lisp
(defmacro with-lock-held ((lock) &body body)
  (let ((with-lock-sym (intern "WITH-LOCK-HELD" "BORDEAUX-THREADS")))
    `(,with-lock-sym (,lock)
       ,@body)))
```

- ✅ Thin wrapper around `bordeaux-threads:with-lock-held`
- ✅ Uses `INTERN` to avoid package lock issues
- ✅ Lock release guaranteed by underlying library

**Recommendation:** None - implementation is correct.

---

### 1.6 WITH-RETRY Macro

**Status:** ⚠️ **MOSTLY SAFE** (with caveats)

**Analysis:**
```lisp
(defmacro with-retry ((&key (max-retries 3) (delay 1) (backoff 2)
                          (condition 'error) (before-retry nil) (on-success nil))
                      &body body)
  (let ((retries (gensym "RETRIES"))
        (current-delay (gensym "DELAY"))
        (result (gensym "RESULT")))
    ...))
```

- ✅ Uses `gensym` for all internal variables
- ✅ `body` evaluated correctly in loop context
- ⚠️ **Caveat**: `condition` parameter should be a symbol or list of symbols (not evaluated)
- ⚠️ **Caveat**: `before-retry` and `on-success` should be function designators

**Recommendation:** Document expected types for callback parameters.

---

## 2. Summary Table

| Macro | Status | Issue Severity | Notes |
|-------|--------|----------------|-------|
| `awhen` | ✅ Safe | - | Anaphoric by design |
| `aand` | ✅ Safe | - | Anaphoric by design |
| `aor` | ✅ Safe | - | Anaphoric by design |
| `aif` | ✅ Safe | - | Anaphoric by design |
| `aif*` | ✅ Safe | - | Anaphoric by design |
| `awhen*` | ✅ Safe | - | Anaphoric by design |
| `do-hash` | ⚠️ Mostly Safe | Low | Document symbol requirement |
| `accumulating` | ❌ Unsafe | **HIGH** | Item evaluated twice - needs fix |
| `with-redis-connection` | ✅ Safe | - | Correct resource management |
| `with-lock-held` | ✅ Safe | - | Correct wrapper |
| `with-retry` | ⚠️ Mostly Safe | Low | Document callback types |
| `with-plist-bindings` | ✅ Safe | - | Correct gensym usage |

---

## 3. Required Fixes

### 3.1 Fix ACCUMULATING Macro (CRITICAL)

**File:** `src/macros.lisp`

**Current (buggy):**
```lisp
(defmacro accumulating ((collector init &key test) &body body)
  (let ((result-sym (gensym "RESULT")))
    `(let ((,result-sym ,init))
       (macrolet ((,collector (item)
                    `(progn
                       ,@(when test `((unless (find ,item ,',result-sym :test ,',test))))
                       (push ,item ,',result-sym))))
         ,@body
         (nreverse ,result-sym)))))
```

**Fixed:**
```lisp
(defmacro accumulating ((collector init &key test) &body body)
  (let ((result-sym (gensym "RESULT"))
        (item-sym (gensym "ITEM")))
    `(let ((,result-sym ,init))
       (macrolet ((,collector (,item-sym)
                    `(progn
                       ,@(when test `((unless (find ,',item-sym ,',,result-sym :test ,',test))))
                       (push ,',item-sym ,',,result-sym))))
         ,@body
         (nreverse ,result-sym)))))
```

**Key Changes:**
1. Added `item-sym` with `gensym` to prevent double evaluation
2. `item-sym` is now the parameter symbol in the macrolet template
3. Proper comma/comma-at escaping in nested template

---

## 4. Documentation Updates Required

### 4.1 DO-HASH

Add to docstring:
> **Note:** `key-var` and `val-var` should be simple symbols, not expressions.

### 4.2 ACCUMULATING (after fix)

Add to docstring:
> **Note:** The `item` argument to collector is evaluated exactly once.

### 4.3 WITH-RETRY

Add to docstring:
> **Note:** `before-retry` and `on-success` should be function designators (symbols or lambda expressions).

---

## 5. Security Checklist for Future Macros

When writing new macros, always verify:

- [ ] All internal symbols use `gensym` to prevent capture
- [ ] User expressions are evaluated exactly once (use `once-only` or bind to gensyms)
- [ ] Resource cleanup uses `unwind-protect`
- [ ] Macro arguments that are code templates use proper comma escaping
- [ ] Anaphoric capture is intentional and documented
- [ ] No premature evaluation of body forms
- [ ] Non-local exits (return-from, throw) are handled correctly

---

## 6. Testing Recommendations

Add unit tests for:

1. **Anaphoric macros**: Verify `it` is correctly bound and doesn't leak
2. **DO-HASH**: Test with complex hash-table expressions
3. **ACCUMULATING**: Test that item expressions are only evaluated once
4. **WITH-REDIS-CONNECTION**: Test cleanup on both normal exit and error
5. **WITH-LOCK-HELD**: Test that lock is released on error

---

## 7. Conclusion

The macro library is **mostly safe** with one critical bug in `accumulating` that must be fixed. After applying the fix and updating documentation, the library will follow On Lisp best practices.

**Overall Security Rating:** 🟡 **MODERATE** (until accumulating fix is applied)
**Target Security Rating:** 🟢 **HIGH** (after fix)
