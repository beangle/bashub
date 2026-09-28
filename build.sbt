import SasDepends.*
import org.beangle.parent.Settings.*

organization := "org.beangle.sashub"
version := "0.0.8"

scmInfo := Some(
  ScmInfo(
    uri("https://github.com/beangle/sashub"),
    "scm:git@github.com:beangle/sashub.git"
  )
)

developers := List(
  Developer(
    id = "chaostone",
    name = "Tihua Duan",
    email = "duantihua@gmail.com",
    url = uri("http://github.com/duantihua")
  )
)

description := "The Beangle Sas Hub"
homepage := Some(uri("http://beangle.github.io/sashub/index.html"))
resolvers += Resolver.mavenLocal

lazy val root = (project in file("."))
  .enablePlugins(WarPlugin, TomcatPlugin)
  .enablePlugins(AotPlugin,MetaPlugin,ProxyPlugin)
  .settings(
    name := "beangle-sashub",
    common,
    libraryDependencies ++= appDepends,
    snapshotRepoUrl := "https://sas.openurp.net/sas/repo/snapshot/upload/{fileName}",
    crossPaths := false
  )

