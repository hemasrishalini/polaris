/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
import licenses.LicenseNoticeMerge
import publishing.PublishingHelperPlugin
import publishing.digestTaskOutputs
import publishing.signTaskOutputs

plugins {
  id("distribution")
  id("signing")
  id("polaris-spotless")
  id("polaris-reproducible")
}

description = "Apache Polaris Binary Distribution"

apply<PublishingHelperPlugin>()

val adminProject = project(":polaris-admin")
val serverProject = project(":polaris-server")

val adminDistribution by
  configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
  }

val serverDistribution by
  configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
  }

val licenseNotice by
  configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
  }

dependencies {
  adminDistribution(project(":polaris-admin", "distributionElements"))
  serverDistribution(project(":polaris-server", "distributionElements"))
  licenseNotice(project(":polaris-admin", "licenseNoticeElements"))
  licenseNotice(project(":polaris-server", "licenseNoticeElements"))
}

val licenseNoticeMerge by
  tasks.registering(LicenseNoticeMerge::class) { sourceLicenseNotice = licenseNotice }

tasks.named("assembleDist").configure { dependsOn(licenseNoticeMerge) }

distributions {
  main {
    distributionBaseName.set("polaris-bin")
    contents {
      into("admin") { from(adminDistribution) { exclude("quarkus-app-dependencies.txt") } }
      into("server") { from(serverDistribution) { exclude("quarkus-app-dependencies.txt") } }
      into("bin") {
        from("bin/server")
        from("bin/admin")
      }
      from("README.md")
      from(licenseNoticeMerge)
    }
  }
}

val distTar = tasks.named<Tar>("distTar") { compression = Compression.GZIP }

val distZip = tasks.named<Zip>("distZip") {}

val validateDistributionLicenseNotice by
  tasks.registering {
    dependsOn(distTar, distZip)

    doLast {
      // --- Validate ZIP ---
      val zipFile = distZip.get().archiveFile.get().asFile
      if (!zipFile.exists()) {
        throw GradleException("Distribution zip archive was not created: ${zipFile.path}")
      }
      val zipEntries = mutableListOf<String>()
      java.util.zip.ZipFile(zipFile).use { zip ->
        zip.entries().asSequence().forEach { zipEntries.add(it.name) }
      }
      if (zipEntries.none { it.endsWith("/LICENSE") || it == "LICENSE" }) {
        throw GradleException("LICENSE file is missing inside ${zipFile.name}")
      }
      if (zipEntries.none { it.endsWith("/NOTICE") || it == "NOTICE" }) {
        throw GradleException("NOTICE file is missing inside ${zipFile.name}")
      }

      // --- Validate TAR (uses Gradle's built-in Ant tar classes, no extra dependency needed) ---
      val tarFile = distTar.get().archiveFile.get().asFile
      if (!tarFile.exists()) {
        throw GradleException("Distribution tar archive was not created: ${tarFile.path}")
      }
      val tarEntries = mutableListOf<String>()
      java.util.zip.GZIPInputStream(tarFile.inputStream()).use { gzip ->
        org.apache.tools.tar.TarInputStream(gzip).use { tar ->
          var entry = tar.nextEntry
          while (entry != null) {
            tarEntries.add(entry.name)
            entry = tar.nextEntry
          }
        }
      }
      if (tarEntries.none { it.endsWith("/LICENSE") || it == "LICENSE" }) {
        throw GradleException("LICENSE file is missing inside ${tarFile.name}")
      }
      if (tarEntries.none { it.endsWith("/NOTICE") || it == "NOTICE" }) {
        throw GradleException("NOTICE file is missing inside ${tarFile.name}")
      }

      logger.lifecycle("LICENSE and NOTICE validated successfully in both ZIP and TAR archives.")
    }
  }

tasks.named("check").configure { dependsOn(validateDistributionLicenseNotice) }

digestTaskOutputs(distTar)

digestTaskOutputs(distZip)

signTaskOutputs(distTar)

signTaskOutputs(distZip)
