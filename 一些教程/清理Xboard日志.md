# 清理Xboard存放在MySQL5.7里的日志内容

## 使用命令行连接并执行 SQL

1. **进入容器：**

    假设你的 MySQL 容器叫 `mysql`，运行：

    ```bash
    docker exec -it mysql bash
    ```

2. **连接 MySQL：**

    ```bash
    mysql -u root -p
    ```

    系统会提示你输入密码（是你在 Docker 启动时设置的 `MYSQL_ROOT_PASSWORD`）。

3. **选择数据库并清空表内容：**

    ```sql
    USE xboard;
    TRUNCATE TABLE v2_log;
    ```

    或：

    ```sql
    DELETE FROM v2_log;
    ```

    > 推荐使用 `TRUNCATE`，更快并且能重置自增 ID。

## 其他命令

要查看 Docker 中 MySQL 的 `xboard` 数据库里的所有内容，你有几种方式可以做到，下面是推荐的方式和操作示例。

---

### 使用命令行查看数据库内容

#### 步骤 1：进入容器并连接 MySQL

```bash
docker exec -it mysql bash
mysql -u root -p
```

输入密码后进入 MySQL 命令行。

#### 步骤 2：选择数据库

```sql
USE xboard;
```

#### 步骤 3：查看有哪些表

```sql
SHOW TABLES;
```

你会看到类似：

```sql
+----------------+
| Tables_in_xboard |
+----------------+
| v2_log         |
| user_data      |
| config         |
+----------------+
```

---

#### 步骤 4：查看某张表的内容（比如 `v2_log`）

```sql
SELECT * FROM v2_log LIMIT 100;
```

这会显示 `v2_log` 表的前 100 行内容，防止一次性加载太多数据。
