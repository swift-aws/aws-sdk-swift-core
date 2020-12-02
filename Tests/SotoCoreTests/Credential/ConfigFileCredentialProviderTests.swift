//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import struct Foundation.UUID
import NIO
@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest

class ConfigFileCredentialProviderTests: XCTestCase {
    // MARK: - Credential Provider

    func makeContext() -> (CredentialProviderFactory.Context, MultiThreadedEventLoopGroup, HTTPClient) {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        return (.init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger), eventLoopGroup, httpClient)
    }

    func testCredentialProvider() {
        let credentials = ConfigFileLoader.ProfileCredentials(
            accessKey: "foo",
            secretAccessKey: "bar",
            sessionToken: nil,
            roleArn: nil,
            roleSessionName: nil,
            sourceProfile: nil,
            credentialSource: nil
        )
        let (context, eventLoopGroup, httpClient) = self.makeContext()

        let provider = try? ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            config: nil,
            context: context,
            endpoint: nil
        )
        XCTAssertEqual((provider as? StaticCredential)?.accessKeyId, "foo")
        XCTAssertEqual((provider as? StaticCredential)?.secretAccessKey, "bar")

        XCTAssertNoThrow(try provider?.shutdown(on: context.eventLoop).wait())
        XCTAssertNoThrow(try httpClient.syncShutdown())
        XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
    }

    func testCredentialProviderSTSAssumeRole() {
        let credentials = ConfigFileLoader.ProfileCredentials(
            accessKey: "foo",
            secretAccessKey: "bar",
            sessionToken: nil,
            roleArn: "arn",
            roleSessionName: nil,
            sourceProfile: "baz",
            credentialSource: nil
        )
        let (context, eventLoopGroup, httpClient) = self.makeContext()

        let provider = try? ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            config: nil,
            context: context,
            endpoint: nil
        )
        XCTAssertTrue(provider is STSAssumeRoleCredentialProvider)
        XCTAssertEqual((provider as? STSAssumeRoleCredentialProvider)?.request.roleArn, "arn")

        XCTAssertNoThrow(try provider?.shutdown(on: context.eventLoop).wait())
        XCTAssertNoThrow(try httpClient.syncShutdown())
        XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
    }

    func testCredentialProviderCredentialSource() {
        let credentials = ConfigFileLoader.ProfileCredentials(
            accessKey: "foo",
            secretAccessKey: "bar",
            sessionToken: nil,
            roleArn: "arn",
            roleSessionName: nil,
            sourceProfile: nil,
            credentialSource: .ec2Instance
        )
        let (context, eventLoopGroup, httpClient) = self.makeContext()

        do {
            _ = try ConfigFileCredentialProvider.credentialProvider(
                from: credentials,
                config: nil,
                context: context,
                endpoint: nil
            )
        } catch {
            XCTAssertEqual(error as? CredentialProviderError, .notSupported)
        }

        XCTAssertNoThrow(try httpClient.syncShutdown())
        XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
    }

    // MARK: - Config File Credentials Provider

    func testConfigFileSuccess() {
        let credentials = """
        [default]
        aws_access_key_id = AWSACCESSKEYID
        aws_secret_access_key = AWSSECRETACCESSKEY
        """
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait())
        XCTAssertEqual(credential?.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "AWSSECRETACCESSKEY")
    }

    func testAWSProfileConfigFile() {
        let credentials = """
        [test-profile]
        aws_access_key_id = TESTPROFILE-AWSACCESSKEYID
        aws_secret_access_key = TESTPROFILE-AWSSECRETACCESSKEY
        """
        Environment.set("test-profile", for: "AWS_PROFILE")
        defer { Environment.unset(name: "AWS_PROFILE") }

        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait())
        XCTAssertEqual(credential?.accessKeyId, "TESTPROFILE-AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "TESTPROFILE-AWSSECRETACCESSKEY")
    }

    func testConfigFileNotAvailable() {
        let filename = "credentials_not_existing"
        let filenameURL = URL(fileURLWithPath: filename)

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger))

        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait()) { error in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testConfigFileShutdown() {
        let client = createAWSClient(credentialProvider: .configFile())
        XCTAssertNoThrow(try client.syncShutdown())
    }

    // MARK: - Role ARN Credential

    func testRoleARNSourceProfile() throws {
        let profile = "user1"

        // Prepare mock STSAssumeRole credentials
        let stsCredentials = STSCredentials(
            accessKeyId: "STSACCESSKEYID",
            expiration: Date().addingTimeInterval(60),
            secretAccessKey: "STSSECRETACCESSKEY",
            sessionToken: "STSSESSIONTOKEN"
        )

        // Prepare credentials file
        let credentialsFile = """
        [default]
        aws_access_key_id = DEFAULTACCESSKEY
        aws_secret_access_key=DEFAULTSECRETACCESSKEY
        aws_session_token =TOKENFOO

        [\(profile)]
        role_arn       = arn:aws:iam::000000000000:role/test-sts-assume-role
        source_profile = default
        color          = ff0000
        """
        let credentialsFilePath = "credentials-" + UUID().uuidString
        try credentialsFile.write(toFile: credentialsFilePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: credentialsFilePath) }

        // Prepare config file
        let configFile = """
        region=us-west-2
        role_session_name =testRoleARNSourceProfile
        """
        let configFilePath = "config-" + UUID().uuidString
        try configFile.write(toFile: configFilePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: configFilePath) }

        // Prepare test server and AWS client
        let testServer = AWSTestServer(serviceProtocol: .xml)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)

        // Here we use `.custom` provider factory, since we need to inject the testServer endpoint
        let client = createAWSClient(credentialProvider: .custom({ (context) -> CredentialProvider in
            ConfigFileCredentialProvider(
                credentialsFilePath: credentialsFilePath,
                configFilePath: configFilePath,
                profile: profile,
                context: context,
                endpoint: testServer.address
            )
        }), httpClientProvider: .shared(httpClient))

        try testServer.processRaw { _ in
            let output = STSAssumeRoleResponse(credentials: stsCredentials)
            let xml = try XMLEncoder().encode(output)
            let byteBuffer = ByteBufferAllocator().buffer(string: xml.xmlString)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
            return .result(response)
        }

        let credentials = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next(),
                                                                      logger: TestEnvironment.logger).wait()
        XCTAssertEqual(credentials.accessKeyId, stsCredentials.accessKeyId)
        XCTAssertEqual(credentials.secretAccessKey, stsCredentials.secretAccessKey)

        try httpClient.syncShutdown()
        try testServer.stop()
        try client.syncShutdown()
        try httpClient.syncShutdown()
    }
}
