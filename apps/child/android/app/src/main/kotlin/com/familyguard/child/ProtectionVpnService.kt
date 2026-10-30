package com.familyguard.child

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class ProtectionVpnService : VpnService() {
    private val warningStarted = mutableMapOf<String, Long>()
    private var lastWarningToast = -5_000L
    private var wasFriendly = false
    private var tunFd: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)
    private var worker: Thread? = null
    private lateinit var activityDatabase: ActivityLogDatabase

    override fun onCreate() {
        super.onCreate()
        activityDatabase = ActivityLogDatabase(applicationContext)
        activeInstance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                ActivityLogDatabase.saveProtectionState(this, false)
                stopFilter()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val list = intent.getStringArrayListExtra(EXTRA_DOMAINS)
                if (list != null) {
                    blockedDomains.clear()
                    list.forEach { blockedDomains.add(normalize(it)) }
                    ActivityLogDatabase.saveBlockedDomains(this, blockedDomains)
                }
                return START_STICKY
            }
            else -> {
                val list = intent?.getStringArrayListExtra(EXTRA_DOMAINS)
                    ?: ArrayList(ActivityLogDatabase.loadBlockedDomains(this))
                blockedDomains.clear()
                list.forEach { blockedDomains.add(normalize(it)) }
                ActivityLogDatabase.saveBlockedDomains(this, blockedDomains)
                ActivityLogDatabase.saveProtectionState(this, true)
                startFilter()
            }
        }
        return START_STICKY
    }

    private fun startFilter() {
        if (running.get()) return
        startForeground(NOTIFICATION_ID, buildNotification())
        val builder = Builder()
            .setSession("Family Guard")
            .setMtu(1500)
            .addAddress("10.0.0.2", 32)
            .addDnsServer("10.0.0.1")
            .addRoute("10.0.0.1", 32)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        tunFd = builder.establish()
        if (tunFd == null) {
            Log.e(TAG, "Failed to establish VPN")
            ActivityLogDatabase.saveProtectionState(this, false)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        running.set(true)
        isRunning = true
        worker = thread(name = "fg-vpn-dns", start = true) { vpnLoop() }
    }

    private fun stopFilter() {
        running.set(false)
        isRunning = false
        try {
            tunFd?.close()
        } catch (_: Exception) {
        }
        tunFd = null
        worker = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun vpnLoop() {
        val fd = tunFd ?: return
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val packet = ByteArray(32767)

        while (running.get()) {
            try {
                val length = input.read(packet)
                if (length <= 0) continue
                handlePacket(packet, length, output)
            } catch (e: Exception) {
                if (running.get()) Log.w(TAG, "VPN loop: ${e.message}")
                break
            }
        }
    }

    private fun handlePacket(packet: ByteArray, length: Int, output: FileOutputStream) {
        if (length < 28) return
        val version = (packet[0].toInt() shr 4) and 0xF
        if (version != 4) return
        val ihl = (packet[0].toInt() and 0xF) * 4
        if (length < ihl + 8) return
        val protocol = packet[9].toInt() and 0xFF
        if (protocol != 17) return // UDP only

        val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
        val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
        if (dstPort != 53) return

        val dnsOffset = ihl + 8
        val dnsLen = length - dnsOffset
        if (dnsLen < 12) return

        val qname = parseDnsName(packet, dnsOffset, length) ?: return
        val domain = normalize(qname)
        val blocked = isBlocked(domain)
        val now = android.os.SystemClock.elapsedRealtime()
        val friendly = getSharedPreferences("safety_mode", MODE_PRIVATE).getString("mode", "strict") == "friendly"
        if (friendly != wasFriendly) {
            warningStarted.clear()
            wasFriendly = friendly
        }
        // Block unsafe DNS immediately, but give a local warning before reporting.
        warningStarted.entries.removeAll { now - it.value > 300_000L }
        val started = warningStarted[domain]
        val warning = blocked && friendly && (started == null || now - started < 20_000L)
        if (warning && started == null) warningStarted[domain] = now
        if (warning && now - lastWarningToast > 5_000L) {
            lastWarningToast = now
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(this, "This website breaks your family rules. Please leave now. Further attempts after 20 seconds are reported.", android.widget.Toast.LENGTH_LONG).show()
            }
        }
        // Local warnings never enter the parent activity queue.
        try {
            if (!warning) activityDatabase.recordDomain(domain, if (blocked) "blocked" else "allowed", System.currentTimeMillis())
        } catch (e: Exception) {
            Log.e(TAG, "Could not persist DNS activity for $domain", e)
        }
        emitDomain(domain, if (warning) "warning" else if (blocked) "blocked" else "allowed")

        if (blocked) {
            val response = buildNxDomain(packet, dnsOffset, dnsLen)
            val out = wrapUdpResponse(packet, ihl, srcPort, response)
            if (out != null) {
                output.write(out)
            }
            return
        }

        // Forward to upstream DNS
        try {
            val socket = DatagramSocket()
            protect(socket)
            socket.soTimeout = 3000
            val upstream = InetAddress.getByName(UPSTREAM_DNS)
            val req = DatagramPacket(
                packet.copyOfRange(dnsOffset, dnsOffset + dnsLen),
                dnsLen,
                upstream,
                53,
            )
            socket.send(req)
            val buf = ByteArray(4096)
            val resp = DatagramPacket(buf, buf.size)
            socket.receive(resp)
            socket.close()
            val out = wrapUdpResponse(packet, ihl, srcPort, buf.copyOf(resp.length))
            if (out != null) output.write(out)
        } catch (e: Exception) {
            Log.w(TAG, "DNS forward failed for $domain: ${e.message}")
        }
    }

    private fun isBlocked(domain: String): Boolean {
        for (blocked in blockedDomains) {
            if (domain == blocked || domain.endsWith(".$blocked")) return true
        }
        return false
    }

    private fun parseDnsName(data: ByteArray, dnsOffset: Int, totalLen: Int): String? {
        var pos = dnsOffset + 12
        if (pos >= totalLen) return null
        val parts = mutableListOf<String>()
        var jumps = 0
        while (pos < totalLen && jumps < 10) {
            val len = data[pos].toInt() and 0xFF
            if (len == 0) break
            if ((len and 0xC0) == 0xC0) {
                // compression pointer — stop gathering for query name simplicity
                break
            }
            pos++
            if (pos + len > totalLen) return null
            parts.add(String(data, pos, len, Charsets.US_ASCII))
            pos += len
            jumps++
        }
        return if (parts.isEmpty()) null else parts.joinToString(".")
    }

    private fun buildNxDomain(request: ByteArray, dnsOffset: Int, dnsLen: Int): ByteArray {
        val resp = request.copyOfRange(dnsOffset, dnsOffset + dnsLen)
        // Flags: response + recursion + name error (RCODE=3)
        resp[2] = (0x81).toByte()
        resp[3] = (0x83).toByte()
        // ANCOUNT / NSCOUNT / ARCOUNT = 0
        resp[6] = 0
        resp[7] = 0
        resp[8] = 0
        resp[9] = 0
        resp[10] = 0
        resp[11] = 0
        return resp
    }

    private fun wrapUdpResponse(
        original: ByteArray,
        ihl: Int,
        clientPort: Int,
        dnsPayload: ByteArray,
    ): ByteArray? {
        val udpLen = 8 + dnsPayload.size
        val totalLen = ihl + udpLen
        val out = ByteArray(totalLen)

        // Copy original IP header then swap src/dst
        System.arraycopy(original, 0, out, 0, ihl)
        // Swap IP addresses (bytes 12-15 <-> 16-19)
        for (i in 0 until 4) {
            val tmp = out[12 + i]
            out[12 + i] = out[16 + i]
            out[16 + i] = tmp
        }
        out[2] = ((totalLen shr 8) and 0xFF).toByte()
        out[3] = (totalLen and 0xFF).toByte()
        out[8] = 64 // TTL
        out[10] = 0
        out[11] = 0
        // Recompute IP checksum
        val ipChecksum = checksum(out, 0, ihl)
        out[10] = ((ipChecksum shr 8) and 0xFF).toByte()
        out[11] = (ipChecksum and 0xFF).toByte()

        // UDP header
        val udpOffset = ihl
        out[udpOffset] = 0
        out[udpOffset + 1] = 53 // src port 53
        out[udpOffset + 2] = ((clientPort shr 8) and 0xFF).toByte()
        out[udpOffset + 3] = (clientPort and 0xFF).toByte()
        out[udpOffset + 4] = ((udpLen shr 8) and 0xFF).toByte()
        out[udpOffset + 5] = (udpLen and 0xFF).toByte()
        out[udpOffset + 6] = 0
        out[udpOffset + 7] = 0
        System.arraycopy(dnsPayload, 0, out, udpOffset + 8, dnsPayload.size)
        return out
    }

    private fun checksum(buf: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        while (i < offset + length - 1) {
            sum += ((buf[i].toInt() and 0xFF) shl 8) or (buf[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (length % 2 != 0) {
            sum += (buf[offset + length - 1].toInt() and 0xFF) shl 8
        }
        while (sum ushr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum ushr 16)
        }
        return sum.inv() and 0xFFFF
    }

    private fun buildNotification(): Notification {
        val channelId = "family_guard_vpn"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Family Guard Protection",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Family Guard is protecting this device")
            .setContentText("DNS filter VPN is active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        stopFilter()
        activeInstance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        ActivityLogDatabase.saveProtectionState(this, false)
        stopFilter()
        stopSelf()
        super.onRevoke()
    }

    companion object {
        private const val TAG = "ProtectionVpn"
        private const val NOTIFICATION_ID = 42
        private const val UPSTREAM_DNS = "8.8.8.8"

        const val ACTION_START = "com.familyguard.child.START_VPN"
        const val ACTION_STOP = "com.familyguard.child.STOP_VPN"
        const val ACTION_UPDATE = "com.familyguard.child.UPDATE_VPN"
        const val EXTRA_DOMAINS = "blockedDomains"

        @Volatile
        var isRunning: Boolean = false

        @Volatile
        var activeInstance: ProtectionVpnService? = null

        @Volatile
        var usageSink: ((Map<String, Any>) -> Unit)? = null

        val blockedDomains: MutableSet<String> =
            ConcurrentHashMap.newKeySet()

        var domainSink: ((String, String) -> Unit)? = null

        fun normalize(domain: String): String {
            var d = domain.trim().lowercase()
            if (d.startsWith("www.")) d = d.substring(4)
            return d
        }

        fun emitDomain(domain: String, action: String) {
            try {
                domainSink?.invoke(domain, action)
            } catch (_: Exception) {
            }
        }
    }
}
