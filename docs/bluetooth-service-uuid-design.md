# from GPT

结论先说：这套 A100 GATT 服务由 TV 端提供、App 端只做 Central 客户端 的架构是对的、可落地。但要确保在 Android TV 端把“可被扫描 + 可连接 + 可通知”的细节都配齐，否则会出现“App 端逻辑没问题、但真机扫不到/连不上/不稳定”的坑。下面给你一次性把关键点、易错点和落地代码骨架补齐。

⸻

总体是否合理
• ✅ 职责划分：TV=BLE Peripheral（GATT Server + Advertising），App=Central（扫描/连接/读写/订阅 notify）。合理。
• ✅ 服务抽象：A100 服务 + 一组特征（设备信息/扫描请求/扫描结果/握手会话/配网请求/状态）清晰，贴合配网流程。
• ✅ 广播策略：在广告里放 A100 Service UUID，App 端按服务过滤，能显著降噪。
• ✅ 安全：你们之前设计了 ECDH+AES-GCM，会话态加密，没问题。

⸻

TV 端必须确认/补充的事项（很关键） 1. 硬件支持 BLE 外设模式
很多 Android TV 盒子只支持 Central，不支持 Peripheral 广播。开工前先检查：

val pm = context.packageManager
val hasLE = pm.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
val advertiser = BluetoothAdapter.getDefaultAdapter()?.bluetoothLeAdvertiser
val supportAdv = BluetoothAdapter.getDefaultAdapter()?.isMultipleAdvertisementSupported == true
// hasLE && supportAdv && advertiser != null 才能做广播

    2.	系统/权限位（Android 12+/13+）
    •	BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT, BLUETOOTH_SCAN（运行时权限）
    •	ACCESS_FINE_LOCATION（仅 Android 11- 扫描需要 & 要求系统定位开关 ON）
    •	uses-feature android.hardware.bluetooth_le
    •	你的 APP 最好是 系统签名/DO（Device Owner），以便后续静默配 Wi-Fi。

AndroidManifest.xml（TV 端）示例：

<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<!-- Android 11 及以下才需要 -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

    3.	广播里要带“可唯一匹配”的信息

仅放 Service UUID 只能筛掉无关设备，无法区分多台同型号。
强烈建议把 deviceId 的短指纹（或 SN 前缀）放进 Manufacturer Data 或 Service Data，App 端用它跟二维码一一对应（你们二维码已有 deviceId，刚好配套）。 4. GATT Characteristic 的属性 & 权限
• 读（PROPERTY_READ | PERMISSION_READ）、写（PROPERTY_WRITE | PERMISSION_WRITE）、通知（PROPERTY_NOTIFY）要匹配；
• 所有 敏感特征（Provision_Request、Handshake）只接受会话加密后的数据；
• Provision_Status 用 Notify 主动推送阶段/错误码。 5. MTU 与分片
• 连接后尝试 requestMtu(247)；
• 封包按你文档里的 seq/idx 分片重组，避免长帧被系统截断；
• 遇到较小 MTU（部分电视或低端芯片）要降级。 6. 连接参数/稳定性
• 设定合适 Connection Priority（CONNECTION_PRIORITY_HIGH 在握手/大包阶段，完成后降回 BALANCED）；
• 处理好 多手机并发：一次只允许 1 个 Central 进入“配网会话”。 7. Wi-Fi 静默配置能力
• 这属于 TV 侧系统权限：Device Owner / 系统签名 App 调系统接口添加/切换 Wi-Fi；
• 普通第三方 App 在 Android 10+ 不允许静默写 Wi-Fi。

⸻

TV 端落地骨架（Android/Kotlin）

1. 注册 GATT Server + Service/Characteristic

class BleProvisionService(private val ctx: Context) {
private val adapter = BluetoothAdapter.getDefaultAdapter()
private val gattServer = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
.openGattServer(ctx, gattServerCallback)

    private val SERVICE_UUID = UUID.fromString("0000A100-0000-1000-8000-00805F9B34FB")
    private val CH_DEV_INFO   = UUID.fromString("0000A101-0000-1000-8000-00805F9B34FB")
    private val CH_SCAN_REQ   = UUID.fromString("0000A102-0000-1000-8000-00805F9B34FB")
    private val CH_SCAN_RES   = UUID.fromString("0000A103-0000-1000-8000-00805F9B34FB")
    private val CH_SESSION    = UUID.fromString("0000A104-0000-1000-8000-00805F9B34FB")
    private val CH_HANDSHAKE  = UUID.fromString("0000A105-0000-1000-8000-00805F9B34FB")
    private val CH_PROVISION  = UUID.fromString("0000A106-0000-1000-8000-00805F9B34FB")
    private val CH_STATUS     = UUID.fromString("0000A107-0000-1000-8000-00805F9B34FB")
    private val CH_OOB_QR     = UUID.fromString("0000A108-0000-1000-8000-00805F9B34FB")

    fun setupGatt() {
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        service.addCharacteristic(BluetoothGattCharacteristic(
            CH_DEV_INFO,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        ))

        service.addCharacteristic(BluetoothGattCharacteristic(
            CH_SCAN_REQ,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        ))

        val scanRes = BluetoothGattCharacteristic(
            CH_SCAN_RES,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        service.addCharacteristic(scanRes)

        service.addCharacteristic(BluetoothGattCharacteristic(
            CH_SESSION,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        ))

        service.addCharacteristic(BluetoothGattCharacteristic(
            CH_HANDSHAKE,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        ))

        service.addCharacteristic(BluetoothGattCharacteristic(
            CH_PROVISION,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        ))

        val status = BluetoothGattCharacteristic(
            CH_STATUS,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        service.addCharacteristic(status)

        service.addCharacteristic(BluetoothGattCharacteristic(
            CH_OOB_QR,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        ))

        gattServer.addService(service)
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) { /* state machine */ }

        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            // DEV_INFO / SESSION_NONCE / OOB_QR -> 返回 JSON/CBOR（必要时分片）
            // gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, payload)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray
        ) {
            // SCAN_REQ / HANDSHAKE / PROVISION -> 解析帧，驱动流程
            if (responseNeeded) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }

        // 需要 notify 时：gattServer.notifyCharacteristicChanged(device, ch, false, value)
    }

}

2. 开启广播（包含 Service UUID + 厂商数据短指纹）

fun startAdvertising(deviceIdFingerprint: ByteArray) {
val advertiser = adapter.bluetoothLeAdvertiser ?: return

    val settings = AdvertiseSettings.Builder()
        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
        .setConnectable(true)
        .build()

    val data = AdvertiseData.Builder()
        .setIncludeDeviceName(true) // 本地名如 "AI-TV-XXXX"
        .addServiceUuid(ParcelUuid(SERVICE_UUID))
        .addManufacturerData(0x1234 /* 公司ID */, deviceIdFingerprint) // 放短指纹或短SN
        .build()

    advertiser.startAdvertising(settings, data, object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {}
        override fun onStartFailure(errorCode: Int) { /* 重试/上报 */ }
    })

}

3. MTU、分片、状态机
   连接回调中请求较大 MTU；收发长帧使用你的分片协议；状态机 IDLE→HANDSHAKE→SCANNING→PROVISIONING→ONLINE/ERROR。

⸻

App 端（Flutter）需要注意的区别
• iOS：DiscoveredDevice.id 是系统 UUID，不等于 MAC，也不等于你二维码里的 deviceId；只能靠广告数据里的短指纹/短 SN 来匹配。
• Android：多数能拿到 MAC（但 12+ 也可能随机化）；仍建议统一走“广告中的短指纹”来跨平台匹配。
• 扫描时尽量 withServices = [A100_UUID]，并在回调里解析 manufacturerData/serviceData，只保留“指纹命中”的那一个；对结果做 去重（同一设备多次回调）。

⸻

设计微调建议（锦上添花）
• CBOR/Protobuf 替代 JSON（GATT 传输更省字节，易分片）。
• 握手失败/超时 自动回退到 SoftAP；BLE 仍可做“发现 + 拉起 AP”提示。
• 批量产测/FCT 提前验证：A100 广播、MTU、分片、错误码全链路。
• 密钥存储：TV 公私钥放 Keystore/TEE（如可用），App 端会话密钥只在内存。

⸻

总结
• A100 放在 TV 端是对的，App 端只做 Central。
• 真机上线要特别确认 TV 是否支持 BLE 外设广播、权限、广播里带唯一指纹、GATT 属性匹配、MTU/分片。
• 我上面给了 Android TV 侧的 最小骨架（GATT + 广播），你们可以直接按这个填充业务逻辑。

需要的话，我可以把短指纹格式（如 SHA256(pk) 前 6–8 字节）与 Flutter 端解析/匹配代码也一起给到你，做到“扫码 → 唯一匹配 → 握手”的端到端模板。
