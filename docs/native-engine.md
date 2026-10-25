# native engine

bashub 用一个 `native` engine 和一个 `tar.gz` artifact 描述 GraalVM native-image 等可执行包。

## 配置

```xml
<native-repo remote="${bas_remote_url}/native" token="..."/>

<engines>
  <engine name="native" type="native" version="1"/>
</engines>

<farms>
  <farm name="portal" engine="native">
    <server name="app1" http="8080"/>
  </farm>
</farms>

<webapps>
  <webapp
    uri="gav://org.beangle.ems:beangle-ems-portal:tar.gz:linux-amd64:4.20.15-SNAPSHOT"
    path="/"
    run-at="portal.app1"/>
</webapps>
```

- `artifact.packaging = tar.gz`
- `artifact.classifier` 是平台标签，如 `linux-amd64`
- `artifact.exec` 可选，缺省用 artifactId；相对最终 `servers/<server>` 目录
- 一个 native server 只允许一个 webapp

## SPA

- 组件打包类型增加 `tar.gz`
- 组件增加“可执行文件”
- 引擎类型增加 `native`
- server.xml 自动生成 `<native-repo remote="${bas_remote_url}/native">`

## 正式版 / SNAPSHOT

native 本地仓库和远端 `/native` 都只有一个根：

```text
<group>/<artifact>/<version>/<name>-<version>-<classifier>.tar.gz
```

`-SNAPSHOT` 只影响版本目录名。jstart 在本地命中 SNAPSHOT 时会比对远端 `.sha1`，同名覆盖后自动刷新。
