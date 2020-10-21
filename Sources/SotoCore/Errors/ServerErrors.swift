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

// THIS FILE IS AUTOMATICALLY GENERATED by https://github.com/soto-project/soto-core/scripts/generate-errors.swift. DO NOT EDIT.

import NIOHTTP1

public struct AWSServerError: AWSErrorType {
    enum Code: String {
        case internalFailure = "InternalFailure"
        case serviceUnavailable = "ServiceUnavailable"
    }
    private let error: Code
    public let context: AWSErrorContext?

    /// initialize AWSServerError
    public init?(errorCode: String, context: AWSErrorContext) {
        var errorCode = errorCode
        // remove "Exception" suffix
        if errorCode.hasSuffix("Exception") {
            errorCode = String(errorCode.dropLast(9))
        }
        guard let error = Code(rawValue: errorCode) else { return nil }
        self.error = error
        self.context = context
    }
    
    internal init(_ error: Code, context: AWSErrorContext? = nil) {
        self.error = error
        self.context = context
    }

    /// return error code string
    public var errorCode: String { error.rawValue }

    // The request processing has failed because of an unknown error, exception or failure.
    public static var internalFailure:AWSServerError { .init(.internalFailure) }
    // The request has failed due to a temporary failure of the server.
    public static var serviceUnavailable:AWSServerError { .init(.serviceUnavailable) }
}

extension AWSServerError: Equatable {
    public static func == (lhs: AWSServerError, rhs: AWSServerError) -> Bool {
        lhs.error == rhs.error
    }
}

extension AWSServerError : CustomStringConvertible {
    public var description: String {
        return "\(error.rawValue): \(message ?? "")"
    }
}
