import Foundation

public extension API.V1 {
    /// The Chain API.
    struct Chain { private init() {} }
}

public extension API.V1.Chain {
    /// Type representing user resources from, the eosio.system contract.
    struct UserResources: ABICodable, Equatable, Hashable {
        public let owner: Name
        public let netWeight: Asset
        public let cpuWeight: Asset
        public let ramBytes: FCInt<Int64>
    }

    /// Type representing delegated bandwidth, from the eosio.system contract.
    struct DelegatedBandwidth: ABICodable, Equatable, Hashable {
        public let from: Name
        public let to: Name
        public let netWeight: Asset
        public let cpuWeight: Asset
    }

    /// Type representing a refund request, from the eosio.system contract.
    struct RefundRequest: ABICodable, Equatable, Hashable {
        public let owner: Name
        public let requestTime: TimePointSec
        public let netAmount: Asset
        public let cpuAmount: Asset
    }

    /// Type representing a refund request, from the eosio.system contract.
    struct VoterInfo: Decodable, Equatable, Hashable {
        public let owner: Name
        public let proxy: Name
        public let producers: [Name]
        public let staked: FCInt<Int64>?
        public let lastVoteWeight: Float64
        public let proxiedVoteWeight: Float64
        public let isProxy: UInt8 // ABI says bool but eosio serializer gives a number?
        // omitted, flags1, reserved2, reserved3
    }

    /// Permission type, only used in chain api.
    struct Permission: ABICodable, Equatable, Hashable {
        public let permName: Name
        public let parent: Name
        public let requiredAuth: Authority
    }

    /// Various details about the blockchain.
    struct GetInfo: Request {
        public static let path = "/v1/chain/get_info"
        public struct Response: Decodable, TaposSource {
            /// Hash representing the last commit in the tagged release.
            public let serverVersion: String
            /// Hash representing the ID of the chain.
            public let chainId: ChainId
            /// Highest block number on the chain
            public let headBlockNum: BlockNum
            /// Highest block number on the chain that has been irreversibly applied to state.
            public let lastIrreversibleBlockNum: BlockNum
            /// Highest block ID on the chain that has been irreversibly applied to state.
            public let lastIrreversibleBlockId: BlockId
            /// Highest block ID on the chain.
            public let headBlockId: BlockId
            /// Highest block unix timestamp.
            public let headBlockTime: TimePoint
            /// Producer that signed the highest block (head block).
            public let headBlockProducer: AccountName
            /// CPU limit calculated after each block is produced, approximately 1000 times `blockCpuLimit`.
            public let virtualBlockCpuLimit: FCInt<UInt64>
            /// NET limit calculated after each block is produced, approximately 1000 times `blockNetLimit`.
            public let virtualBlockNetLimit: FCInt<UInt64>
            /// Actual maximum CPU limit.
            public let blockCpuLimit: FCInt<UInt64>
            /// Actual maximum NET limit.
            public let blockNetLimit: FCInt<UInt64>
            /// String representation of server version - Majorish-Minorish-Patchy.
            /// - Note; Not actually SEMVER.
            public let serverVersionString: String?
            /// Sequential block number representing the best known head in the fork database tree.
            public let forkDbHeadBlockNum: BlockNum?
            /// Hash representing the best known head in the fork database tree.
            public let forkDbHeadBlockId: BlockId?

            public var taposValues: (refBlockNum: UInt16, refBlockPrefix: UInt32, expiration: TimePointSec?) {
                let refBlockId = self.lastIrreversibleBlockId
                let refBlockNum = UInt16(refBlockId.blockNum & 0xFFFF)
                let refBlockPrefix = refBlockId.blockPrefix
                let expiration = TimePointSec(self.headBlockTime.addingTimeInterval(60))
                return (refBlockNum, refBlockPrefix, expiration)
            }
        }

        public init() {}
    }

    struct GetRawAbi: Request {
        public static let path = "/v1/chain/get_raw_abi"
        public struct Response: Decodable {
            public let accountName: Name
            public let codeHash: Checksum256
            public let abiHash: Checksum256
            public let abi: Blob?
            public var decodedAbi: ABI? {
                guard let data = self.abi?.bytes else {
                    return nil
                }
                return try? ABIDecoder.decode(ABI.self, data: data)
            }
        }

        public var accountName: Name

        public init(_ accountName: Name) {
            self.accountName = accountName
        }
    }

    struct GetRawCodeAndAbi: Request {
        public static let path = "/v1/chain/get_raw_code_and_abi"
        public struct Response: Decodable {
            public let accountName: Name
            public let wasm: Blob
            public let abi: Blob
            public var decodedAbi: ABI? {
                return try? ABIDecoder.decode(ABI.self, data: self.abi.bytes)
            }
        }

        public var accountName: Name

        public init(_ accountName: Name) {
            self.accountName = accountName
        }
    }

    /// Get code and ABI.
    /// - Attention: Nodeos sends invalid JSON for this call for some accounts. Use `GetRawAbi` and `GetRawAbi
    struct GetCode: Request {
        public static let path = "/v1/chain/get_code"
        public struct Response: Decodable {
            public let accountName: Name
            public let wast: String
            public let wasm: String
            public let codeHash: Checksum256
            public let abi: ABI?
        }

        public var accountName: Name
        public var codeAsWasm = true

        public init(_ accountName: Name) {
            self.accountName = accountName
        }
    }

    /// Query the contents of EOSIO RAM.
    ///
    /// Some params are unsupported, namely:
    /// - `json`: Whether node should try to decode row data using code abi (we always decode client-side).
    /// - `tableKey`: Deined in api plugin but never actually used.
    /// - `encodeType`: Encoding type of the passed key, redundant, use `keyType` instead.
    /// - `showPayer`: Show the RAM payer of the row, changes response structure in a inconvenient way so not handled.
    struct GetTableRows<T: ABIDecodable>: Request {
        public static var path: String { "/v1/chain/get_table_rows" }
        public struct Response: Decodable {
            public let rows: [T]
            public let more: Bool

            private enum Keys: CodingKey {
                case rows
                case more
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: Keys.self)
                var rowContainer = try container.nestedUnkeyedContainer(forKey: .rows)
                var rows: [T] = []
                while !rowContainer.isAtEnd {
                    let hexValue = try rowContainer.decode(String.self)
                    rows.append(try ABIDecoder.decode(T.self, data: Data(hexEncoded: hexValue)))
                }
                self.rows = rows
                self.more = try container.decode(.more)
            }
        }

        public enum IndexPosition: String, Encodable {
            case primary, secondary, tertiary, fourth, fifth, sixth, seventh, eighth, ninth, tenth
        }

        public enum KeyType: String, Encodable {
            case name, i64, i128, i256, float64, float128, sha256, ripemd160
        }

        /// The name of the smart contract that controls the provided table.
        public var code: Name
        /// The account to which this data belongs.
        public var scope: String
        /// The name of the table to query.
        public var table: Name
        /// Lower lookup bound as string representing `keyType`.
        public var lowerBound: String?
        /// Upper lookup bound as string representing `keyType`.
        public var upperBound: String?
        /// How many results to fetch, defaults to 10 if unset.
        public var limit: UInt32?
        /// Type of key specified by `indexPosition`.
        public var keyType: KeyType = .i64
        /// Position of the index used.
        public var indexPosition: IndexPosition = .primary
        /// Whether to iterate records in reverse order.
        public var reverse: Bool?

        /// Create a new `get_table_rows` request.
        public init(code: Name, table: Name, scope: String) {
            self.code = code
            self.scope = scope
            self.table = table
        }

        /// Create a new `get_table_rows` request with scope set from any type representable by a 64-bit unsigned integer.
        public init<T: RawRepresentable>(code: Name, table: Name, scope: T) where T.RawValue == UInt64 {
            self.code = code
            self.scope = Name(rawValue: scope.rawValue).stringValue
            self.table = table
        }

        /// Create a new `get_table_rows` request with scope from a 64-bit unsigned integer.
        public init(code: Name, table: Name, scope: UInt64) {
            self.code = code
            self.scope = Name(rawValue: scope).stringValue
            self.table = table
        }

        /// Create a new `get_table_rows` request with scope set to the code account.
        public init(code: Name, table: Name) {
            self.code = code
            self.scope = code.stringValue
            self.table = table
        }
    }

    /// Push a transaction.
    struct PushTransaction: Request {
        public static let path = "/v1/chain/push_transaction"
        public struct Response: Decodable {
            public let transactionId: TransactionId
            public let processed: [String: Any]

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: StringCodingKey.self)
                self.transactionId = try container.decode(TransactionId.self, forKey: "transactionId")
                self.processed = try container.decode([String: Any].self, forKey: "processed")
            }
        }

        public var signedTransaction: SignedTransaction

        public init(_ signedTransaction: SignedTransaction) {
            self.signedTransaction = signedTransaction
        }

        public func encode(to encoder: Encoder) throws {
            let packed = try PackedTransaction(self.signedTransaction)
            try packed.encode(to: encoder)
        }
    }

    /// Fetch an EOSIO account.
    struct GetAccount: Request {
    //https://test.proton.eosusa.news/v2/state/get_account?account=revtest
        public static let path = "/v1/chain/get_account"
        public struct Response: Decodable {
            public let accountName: Name
            public let headBlockNum: BlockNum
            public let headBlockTime: TimePoint
            public let privileged: Bool
            public let lastCodeUpdate: TimePoint
            public let created: TimePoint
            public let coreLiquidBalance: Asset?
            public let ramQuota: FCInt<Int64>
            public let netWeight: FCInt<Int64>
            public let cpuWeight: FCInt<Int64>
            public let netLimit: AccountResourceLimit
            public let cpuLimit: AccountResourceLimit
            public let ramUsage: FCInt<Int64>
            public let permissions: [Permission]
            // the following params are from the eosio.system contract
            // these are represented by fc::variant in the api plugin
            // and could be different types on a chain with another system contract
            // most if not all major chains have these so should be ok for now
            // TODO: implement a swift version of fc::variant
            public let totalResources: UserResources?
            public let selfDelegatedBandwidth: DelegatedBandwidth?
            public let refundRequest: RefundRequest?
            public let voterInfo: VoterInfo?
        }

        public var accountName: Name
        public var expectedCoreSymbol: Asset.Symbol?

        public init(_ accountName: Name) {
            self.accountName = accountName
        }
    }
    struct GetAccountDetails: Request {
        public static let path = "/v1/chain/get_account"
        struct Response: Codable {
            public let queryTimeMS: Double
            public let account: Account
            public let links: [JSONAny]
            public let tokens: [Token]
            public let totalActions: Int
            public let actions: [Action]

            enum CodingKeys: String, CodingKey {
                case queryTimeMS = "query_time_ms"
                case account, links, tokens
                case totalActions = "total_actions"
                case actions
            }
        }

        // MARK: - Account
        struct Account: Codable {
            let accountName: AccountName
            let headBlockNum: Int
            let headBlockTime: String
            let privileged: Bool
            let lastCodeUpdate, created: String
            let ramQuota, netWeight, cpuWeight: Int
            let netLimit, cpuLimit: Limit
            let ramUsage: Int
            let permissions: [PermissionElement]
            let totalResources: TotalResources
            let selfDelegatedBandwidth, refundRequest, voterInfo, rexInfo: JSONNull?
            let subjectiveCPUBillLimit: Limit
            let eosioAnyLinkedActions: [JSONAny]

            enum CodingKeys: String, CodingKey {
                case accountName = "account_name"
                case headBlockNum = "head_block_num"
                case headBlockTime = "head_block_time"
                case privileged
                case lastCodeUpdate = "last_code_update"
                case created
                case ramQuota = "ram_quota"
                case netWeight = "net_weight"
                case cpuWeight = "cpu_weight"
                case netLimit = "net_limit"
                case cpuLimit = "cpu_limit"
                case ramUsage = "ram_usage"
                case permissions
                case totalResources = "total_resources"
                case selfDelegatedBandwidth = "self_delegated_bandwidth"
                case refundRequest = "refund_request"
                case voterInfo = "voter_info"
                case rexInfo = "rex_info"
                case subjectiveCPUBillLimit = "subjective_cpu_bill_limit"
                case eosioAnyLinkedActions = "eosio_any_linked_actions"
            }
        }

        enum AccountName: String, Codable {
            case eosioRAM = "eosio.ram"
            case revtest = "revtest"
            case tokenFaucet = "token.faucet"
        }

        // MARK: - Limit
        struct Limit: Codable {
            let used, available, max: Int
        }

        // MARK: - PermissionElement
        struct PermissionElement: Codable {
            let permName, parent: String
            let requiredAuth: RequiredAuth
            let linkedActions: [JSONAny]

            enum CodingKeys: String, CodingKey {
                case permName = "perm_name"
                case parent
                case requiredAuth = "required_auth"
                case linkedActions = "linked_actions"
            }
        }

        // MARK: - RequiredAuth
        struct RequiredAuth: Codable {
            let threshold: Int
            let keys: [Key]
            let accounts, waits: [JSONAny]
        }

        // MARK: - Key
        struct Key: Codable {
            let key: String
            let weight: Int
        }

        // MARK: - TotalResources
        struct TotalResources: Codable {
            let owner: AccountName
            let netWeight, cpuWeight: String
            let ramBytes: Int

            enum CodingKeys: String, CodingKey {
                case owner
                case netWeight = "net_weight"
                case cpuWeight = "cpu_weight"
                case ramBytes = "ram_bytes"
            }
        }

        // MARK: - Action
        struct Action: Codable {
            let timestamp, actionTimestamp: String
            let blockNum: Int
            let trxID: String
            let act: Act
            let notified: [String]
            let cpuUsageUs, netUsageWords: Int?
            let globalSequence: Int
            let producer: String
            let actionOrdinal, creatorActionOrdinal: Int
            let signatures: [String]?
            let accountRAMDeltas: [AccountRAMDelta]?
            let receiver: Receiver?

            enum CodingKeys: String, CodingKey {
                case timestamp = "@timestamp"
                case actionTimestamp = "timestamp"
                case blockNum = "block_num"
                case trxID = "trx_id"
                case act, notified
                case cpuUsageUs = "cpu_usage_us"
                case netUsageWords = "net_usage_words"
                case globalSequence = "global_sequence"
                case producer
                case actionOrdinal = "action_ordinal"
                case creatorActionOrdinal = "creator_action_ordinal"
                case signatures
                case accountRAMDeltas = "account_ram_deltas"
                case receiver
            }
        }

        // MARK: - AccountRAMDelta
        struct AccountRAMDelta: Codable {
            let account: String
            let delta: Int
        }

        // MARK: - Act
        struct Act: Codable {
            let account: Receiver
            let name: String
            let authorization: [Authorization]
            let data: DataClass
        }

        enum Receiver: String, Codable {
            case eosio = "eosio"
            case eosioToken = "eosio.token"
            case protonWrap = "proton.wrap"
            case tokenFaucet = "token.faucet"
        }

        // MARK: - Authorization
        struct Authorization: Codable {
            let actor: AccountName
            let permission: PermissionEnum
        }

        enum PermissionEnum: String, Codable {
            case active = "active"
        }

        // MARK: - DataClass
        struct DataClass: Codable {
            let from: AccountName?
            let to: String?
            let amount: Double?
            let symbol, quantity: String?
            let memo: String?
            let programID: String?
            let account, protonAccount: AccountName?
            let time: String?
            let bytes: Int?
            let payer: AccountName?
            let receiver: String?
            let active, owner: RequiredAuth?
            let newact: String?
            let creator: AccountName?

            enum CodingKeys: String, CodingKey {
                case from, to, amount, symbol, quantity, memo
                case programID = "programId"
                case account, protonAccount, time, bytes, payer, receiver, active, owner, newact, creator
            }
        }

        // MARK: - Token
        struct Token: Codable {
            let symbol: String
            let precision: Int
            let amount: Double
            let contract: Receiver
        }

        // MARK: - Encode/decode helpers

        class JSONNull: Codable, Hashable {

            public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
                return true
            }

            public var hashValue: Int {
                return 0
            }

            public init() {}

            public required init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if !container.decodeNil() {
                    throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encodeNil()
            }
        }

        class JSONCodingKey: CodingKey {
            let key: String

            required init?(intValue: Int) {
                return nil
            }

            required init?(stringValue: String) {
                key = stringValue
            }

            var intValue: Int? {
                return nil
            }

            var stringValue: String {
                return key
            }
        }

        class JSONAny: Codable {

            let value: Any

            static func decodingError(forCodingPath codingPath: [CodingKey]) -> DecodingError {
                let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode JSONAny")
                return DecodingError.typeMismatch(JSONAny.self, context)
            }

            static func encodingError(forValue value: Any, codingPath: [CodingKey]) -> EncodingError {
                let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Cannot encode JSONAny")
                return EncodingError.invalidValue(value, context)
            }

            static func decode(from container: SingleValueDecodingContainer) throws -> Any {
                if let value = try? container.decode(Bool.self) {
                    return value
                }
                if let value = try? container.decode(Int64.self) {
                    return value
                }
                if let value = try? container.decode(Double.self) {
                    return value
                }
                if let value = try? container.decode(String.self) {
                    return value
                }
                if container.decodeNil() {
                    return JSONNull()
                }
                throw decodingError(forCodingPath: container.codingPath)
            }

            static func decode(from container: inout UnkeyedDecodingContainer) throws -> Any {
                if let value = try? container.decode(Bool.self) {
                    return value
                }
                if let value = try? container.decode(Int64.self) {
                    return value
                }
                if let value = try? container.decode(Double.self) {
                    return value
                }
                if let value = try? container.decode(String.self) {
                    return value
                }
                if let value = try? container.decodeNil() {
                    if value {
                        return JSONNull()
                    }
                }
                if var container = try? container.nestedUnkeyedContainer() {
                    return try decodeArray(from: &container)
                }
                if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self) {
                    return try decodeDictionary(from: &container)
                }
                throw decodingError(forCodingPath: container.codingPath)
            }

            static func decode(from container: inout KeyedDecodingContainer<JSONCodingKey>, forKey key: JSONCodingKey) throws -> Any {
                if let value = try? container.decode(Bool.self, forKey: key) {
                    return value
                }
                if let value = try? container.decode(Int64.self, forKey: key) {
                    return value
                }
                if let value = try? container.decode(Double.self, forKey: key) {
                    return value
                }
                if let value = try? container.decode(String.self, forKey: key) {
                    return value
                }
                if let value = try? container.decodeNil(forKey: key) {
                    if value {
                        return JSONNull()
                    }
                }
                if var container = try? container.nestedUnkeyedContainer(forKey: key) {
                    return try decodeArray(from: &container)
                }
                if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key) {
                    return try decodeDictionary(from: &container)
                }
                throw decodingError(forCodingPath: container.codingPath)
            }

            static func decodeArray(from container: inout UnkeyedDecodingContainer) throws -> [Any] {
                var arr: [Any] = []
                while !container.isAtEnd {
                    let value = try decode(from: &container)
                    arr.append(value)
                }
                return arr
            }

            static func decodeDictionary(from container: inout KeyedDecodingContainer<JSONCodingKey>) throws -> [String: Any] {
                var dict = [String: Any]()
                for key in container.allKeys {
                    let value = try decode(from: &container, forKey: key)
                    dict[key.stringValue] = value
                }
                return dict
            }

            static func encode(to container: inout UnkeyedEncodingContainer, array: [Any]) throws {
                for value in array {
                    if let value = value as? Bool {
                        try container.encode(value)
                    } else if let value = value as? Int64 {
                        try container.encode(value)
                    } else if let value = value as? Double {
                        try container.encode(value)
                    } else if let value = value as? String {
                        try container.encode(value)
                    } else if value is JSONNull {
                        try container.encodeNil()
                    } else if let value = value as? [Any] {
                        var container = container.nestedUnkeyedContainer()
                        try encode(to: &container, array: value)
                    } else if let value = value as? [String: Any] {
                        var container = container.nestedContainer(keyedBy: JSONCodingKey.self)
                        try encode(to: &container, dictionary: value)
                    } else {
                        throw encodingError(forValue: value, codingPath: container.codingPath)
                    }
                }
            }

            static func encode(to container: inout KeyedEncodingContainer<JSONCodingKey>, dictionary: [String: Any]) throws {
                for (key, value) in dictionary {
                    let key = JSONCodingKey(stringValue: key)!
                    if let value = value as? Bool {
                        try container.encode(value, forKey: key)
                    } else if let value = value as? Int64 {
                        try container.encode(value, forKey: key)
                    } else if let value = value as? Double {
                        try container.encode(value, forKey: key)
                    } else if let value = value as? String {
                        try container.encode(value, forKey: key)
                    } else if value is JSONNull {
                        try container.encodeNil(forKey: key)
                    } else if let value = value as? [Any] {
                        var container = container.nestedUnkeyedContainer(forKey: key)
                        try encode(to: &container, array: value)
                    } else if let value = value as? [String: Any] {
                        var container = container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key)
                        try encode(to: &container, dictionary: value)
                    } else {
                        throw encodingError(forValue: value, codingPath: container.codingPath)
                    }
                }
            }

            static func encode(to container: inout SingleValueEncodingContainer, value: Any) throws {
                if let value = value as? Bool {
                    try container.encode(value)
                } else if let value = value as? Int64 {
                    try container.encode(value)
                } else if let value = value as? Double {
                    try container.encode(value)
                } else if let value = value as? String {
                    try container.encode(value)
                } else if value is JSONNull {
                    try container.encodeNil()
                } else {
                    throw encodingError(forValue: value, codingPath: container.codingPath)
                }
            }

            public required init(from decoder: Decoder) throws {
                if var arrayContainer = try? decoder.unkeyedContainer() {
                    self.value = try JSONAny.decodeArray(from: &arrayContainer)
                } else if var container = try? decoder.container(keyedBy: JSONCodingKey.self) {
                    self.value = try JSONAny.decodeDictionary(from: &container)
                } else {
                    let container = try decoder.singleValueContainer()
                    self.value = try JSONAny.decode(from: container)
                }
            }

            public func encode(to encoder: Encoder) throws {
                if let arr = self.value as? [Any] {
                    var container = encoder.unkeyedContainer()
                    try JSONAny.encode(to: &container, array: arr)
                } else if let dict = self.value as? [String: Any] {
                    var container = encoder.container(keyedBy: JSONCodingKey.self)
                    try JSONAny.encode(to: &container, dictionary: dict)
                } else {
                    var container = encoder.singleValueContainer()
                    try JSONAny.encode(to: &container, value: self.value)
                }
            }
        }

    }

    /// Get list of accounts controlled by given public key or authority.
    struct GetAccountsByAuthorizers: Request {
        public static let path = "/v1/chain/get_accounts_by_authorizers"

        /// Account auth response type, used by the `GetAccountsByAuthorizers` api.
        public struct AccountAuthorizer: Decodable, Equatable, Hashable {
            public let accountName: Name
            public let permissionName: Name
            public let authorizingAccount: PermissionLevel?
            public let authorizingKey: PublicKey?
            public let weight: Weight
            public let threshold: UInt32
        }

        public enum AccountOrPermission: Encodable {
            case account(Name)
            case permission(PermissionLevel)

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case let .account(name):
                    try container.encode(name)
                case let .permission(permissionLevel):
                    try container.encode(permissionLevel)
                }
            }
        }

        public struct Response: Decodable {
            /// Account names controlled by key or authority.
            public let accounts: [AccountAuthorizer]
        }

        public var accounts: [AccountOrPermission]?
        public var keys: [PublicKey]?

        public init(keys: [PublicKey]) {
            self.keys = keys
        }

        public init(accounts: [Name]) {
            self.accounts = accounts.map { .account($0) }
        }

        public init(permissions: [PermissionLevel]) {
            self.accounts = permissions.map { .permission($0) }
        }
    }
}
