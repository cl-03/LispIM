# LispIM 宏指南 - On Lisp 风格的抽象艺术

> "Lisp 程序员知道的关于宏的第一件事是：不要使用宏。" - Paul Graham, _On Lisp_

本指南介绍如何使用 `macros.lisp` 中定义的宏来凝练和抽象 LispIM 代码。

## 目录

1. [Anaphoric 宏](#1-anaphoric-宏)
2. [API 处理宏](#2-api-处理宏)
3. [plist 操作宏](#3-plist-操作宏)
4. [资源管理宏](#4-资源管理宏)
5. [迭代宏](#5-迭代宏)
6. [条件绑定宏](#6-条件绑定宏)
7. [最佳实践](#7-最佳实践)

---

## 1. Anaphoric 宏

Anaphoric 宏故意"捕获"变量（如 `it`）以实现更简洁的代码。

### `awhen` - Anaphoric When

```lisp
;; 传统写法
(let ((user (get-user id)))
  (when user
    (print-user user)))

;; 使用 awhen
(awhen (get-user id)
  (print-user it))
```

### `aand` - Anaphoric And

```lisp
;; 传统写法：深层嵌套
(let ((user (get-user id)))
  (when user
    (let ((profile (get-profile user)))
      (when profile
        (let ((name (getf profile :name)))
          (when name
            (format t "Hello, ~a" name)))))))

;; 使用 aand：扁平链式
(aand (get-user id)
      (get-profile it)
      (getf it :name)
      (format t "Hello, ~a" it))
```

### `acond` - Anaphoric Cond

```lisp
;; 传统写法
(cond ((find-user id) (process-user (find-user id)))
      ((find-guest id) (process-guest (find-guest id)))
      (t (create-anonymous)))

;; 使用 acond
(acond ((find-user id) (process-user it))
       ((find-guest id) (process-guest it))
       (t (create-anonymous)))
```

### 使用场景

| 宏 | 适用场景 |
|---|---|
| `awhen` | 单个条件测试后使用结果 |
| `aand` | 多个条件链式测试 |
| `acond` | 多分支选择，每个分支使用测试值 |
| `acase` | case 风格的多分支 |

---

## 2. API 处理宏

### `respond-with` - 快速 API 响应

```lisp
;; 成功响应
(respond-with user-data :success t)

;; 错误响应
(respond-with nil :error-code "NOT_FOUND" :message "User not found")

;; 带消息的成功响应
(respond-with data :success t :message "Operation completed")
```

### `with-api-context` - 统一 API 上下文

```lisp
;; 自动设置 CORS、content-type 和错误处理
(with-api-context
  (let ((result (process-request)))
    (respond-with result :success t)))
```

### `define-api-handler` - 定义 API 处理器

```lisp
(define-api-handler get-user "/api/v1/users/:id"
  :method "GET"
  :auth t
  (let ((user (get-user id)))
    (respond-with user :success t)))

;; 展开后等价于：
(hunchentoot:define-easy-handler (get-user :uri "/api/v1/users/:id") ()
  ;; 自动添加 method 检查、auth 验证、错误处理
  ...)
```

### `api-handler` - 简化处理器体

```lisp
;; 在 define-easy-handler 内部使用
(hunchentoot:define-easy-handler (create-user :uri "/api/v1/users") ()
  (api-handler (:auth t :method "POST" :fields (username password))
    (let ((user (create-user username password)))
      (respond-with user :success t))))
```

---

## 3. plist 操作宏

### `with-plist-bindings` - 批量绑定 plist 键

```lisp
;; 传统写法
(let ((id (getf user :id))
      (name (getf user :name))
      (email (getf user :email)))
  (process id name email))

;; 使用宏
(with-plist-bindings (user :id :name :email)
  (process id name email))
```

### `plist-case` - plist 分支

```lisp
;; 根据 plist 键值分支
(plist-case user
  (:id (process-id id))
  (:name (process-name name))
  (t (process-default)))
```

### `define-getf*` - 定义访问器

```lisp
;; 为用户对象定义访问器
(define-getf* user-id :id "Get user ID")
(define-getf* user-name :name "Get user name")
(define-getf* user-email :email "Get user email")

;; 展开为：
(defun user-id (x) "Get user ID" (getf x :id))
```

---

## 4. 资源管理宏

### `with-redis-connection` - Redis 连接管理

```lisp
;; 自动 pop 连接，unwind-protect 清理，push 回池
(with-redis-connection (conn *redis-pool*)
  (cl-redis:redis-get conn "key"))
```

### `with-db-transaction` - 数据库事务

```lisp
;; 自动 commit/rollback，错误时回滚
(with-db-transaction (conn *db-connection*)
  (insert-user user)
  (insert-profile profile)
  (get-new-user-id))
```

### `with-lock` - 线程锁

```lisp
;; 自动 acquire/release，支持 timeout
(with-lock (*data-lock* :timeout 5.0)
  (update-data new-value))
```

---

## 5. 迭代宏

### `do-hash` - 遍历 hash-table

```lisp
;; 传统写法
(let ((result nil))
  (maphash (lambda (k v)
             (push (cons k v) result))
           hash-table)
  (nreverse result))

;; 使用 do-hash
(let ((result nil))
  (do-hash (k v hash-table (nreverse result))
    (push (cons k v) result)))
```

### `do-plist` - 遍历 plist

```lisp
;; 遍历 plist 键值对
(do-plist (k v plist)
  (format t "~a => ~a~%" k v))
```

### `accumulating` - 累积结果

```lisp
;; 累积唯一元素
(accumulating (result nil :test #'equal)
  (dolist (item items)
    (when (valid-p item)
      (result item))))
```

---

## 6. 条件绑定宏

### `if-let*` - 顺序绑定 if-let

```lisp
;; 传统 if-let 只能绑定一个变量
(if-let ((a (gethash :a x)))
    (if-let ((b (gethash :b x)))
        (+ a b)
      0)
  0)

;; 使用 if-let* 顺序绑定
(if-let* (((gethash :a x))
          ((gethash :b x)))
    (+ a b)
  0)
```

### `when-let*` - 顺序绑定 when-let

```lisp
;; 所有绑定成功后执行
(when-let* ((user (get-user id))
            (profile (get-profile user))
            (name (getf profile :name)))
  (format t "User ~a found" name))
```

### `cond-let` - cond + let 组合

```lisp
;; 先绑定，然后在 cond 子句中使用
(cond-let ((x (get-input)))
  ((> x 10) (process-large x))
  ((> x 0) (process-small x))
  (t (process-zero)))
```

---

## 7. 最佳实践

### ✅ 推荐使用

1. **Anaphoric 宏用于链式调用**
   ```lisp
   (aand (get-user id)
         (get-profile it)
         (getf it :name))
   ```

2. **资源管理宏用于清理**
   ```lisp
   (with-redis-connection (conn *pool*)
     ...)
   ```

3. **响应宏用于 API**
   ```lisp
   (respond-with data :success t)
   ```

### ❌ 避免滥用

1. **不要在宏中隐藏重要逻辑**
   ```lisp
   ;; 坏：逻辑隐藏在宏后面
   (magic-macro-do-everything)
   
   ;; 好：明确表达意图
   (with-transaction ()
     (validate-input)
     (save-to-db)
     (send-notification))
   ```

2. **不要过度使用 anaphoric 宏**
   ```lisp
   ;; 坏：过度链式，难以调试
   (aand (step1)
         (step2 it)
         (step3 it)
         (step4 it)
         (step5 it)
         (step6 it))
   
   ;; 好：适度分解
   (let ((result (step1)))
     (when result
       (let ((intermediate (step2 result)))
         ...)))
   ```

3. **宏名要清晰**
   ```lisp
   ;; 坏：不清晰的宏名
   (with-stuff () ...)
   
   ;; 好：描述性名称
   (with-database-transaction () ...)
   ```

---

## 性能考虑

| 宏类型 | 性能影响 | 说明 |
|---|---|---|
| Anaphoric 宏 | 无 | 纯语法糖，展开后与普通代码相同 |
| 资源管理宏 | 微小 | unwind-protect 有轻微开销 |
| 迭代宏 | 无 | 展开为标准循环 |
| 条件绑定宏 | 无 | 纯语法糖 |

---

## 调试宏展开

使用 SBCL 的 `macroexpand-1` 和 `macroexpand` 查看宏展开：

```lisp
;; 查看单步展开
(macroexpand-1 '(awhen (get-user id) (print it)))

;; 查看完全展开
(macroexpand '(awhen (get-user id) (print it)))

;; 在编译时打印展开
(setf *print-expand* t)
```

---

## 学习资源

1. **On Lisp** - Paul Graham (1993)
   - 免费在线版：http://www.paulgraham.com/onlisp.html
   - 重点章节：Chapter 8 (Anaphoric Macros), Chapter 10 (Resource Management)

2. **Common Lisp Cookbook - Macros**
   - https://common-lisp.net/project/cl-cookbook/macros.html

3. **Practical Common Lisp**
   - Chapter 8: "A Macro Example"
   - Chapter 10: "Practical Macro Techniques"

---

## 总结

> 宏的目标不是写更少的代码，而是写更清晰的代码。

使用这些宏时，始终问自己：
- 这使代码更清晰还是更晦涩？
- 新团队成员能理解这个宏吗？
- 调试时会更容易还是更困难？

如果答案是负面的，就使用普通函数和标准 Lisp 结构。
