// Package bridge exposes a gomobile-compatible API for running Mihomo inside
// an iOS Network Extension. Exported names are prefixed with Bridge by gomobile.
package bridge

import (
	"fmt"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"github.com/metacubex/sing/common/control"

	_ "golang.org/x/mobile/bind"
)

var (
	mu                    sync.Mutex
	running               bool
	tunFdGlobal           int32 = -1
	tunIsSocketPair       bool
	outboundInterfaceName string

	logFile   *os.File
	logFileMu sync.Mutex
	logOnce   sync.Once
)

// SetLogFile appends mihomo engine logs to a shared file (tunnel.log).
func SetLogFile(path string) error {
	logFileMu.Lock()
	if logFile != nil {
		_ = logFile.Close()
		logFile = nil
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		logFileMu.Unlock()
		return err
	}
	logFile = f
	logFileMu.Unlock()

	logOnce.Do(func() {
		sub := log.Subscribe()
		go func() {
			for event := range sub {
				logFileMu.Lock()
				if logFile != nil {
					fmt.Fprintf(logFile, "[Mihomo/%s] %s\n", event.LogLevel, event.Payload)
				}
				logFileMu.Unlock()
			}
		}()
	})
	return nil
}

// SetOutboundInterface forces dialer bind to Wi‑Fi/cellular (en0 / pdp_ip0).
// Without this, Go sockets often follow the VPN default route into utun → no net.
func SetOutboundInterface(name string) {
	mu.Lock()
	outboundInterfaceName = strings.TrimSpace(name)
	mu.Unlock()
}

func init() {
	debug.SetGCPercent(5)
	// Stay under Network Extension jetsam (~15–50MB depending on iOS).
	// gVisor TCP stack needs more headroom than system-only UDP/DNS path.
	debug.SetMemoryLimit(24 * 1024 * 1024)
	runtime.GOMAXPROCS(2)
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		for range ticker.C {
			runtime.GC()
			debug.FreeOSMemory()
		}
	}()
}

// SetHomeDir sets Mihomo home directory (config + geo data).
func SetHomeDir(path string) {
	constant.SetHomeDir(path)
	constant.SetConfig(filepath.Join(path, "config.yaml"))
}

// SetConfig writes YAML config into the home directory.
func SetConfig(yamlContent string) error {
	homeDir := constant.Path.HomeDir()
	return os.WriteFile(filepath.Join(homeDir, "config.yaml"), []byte(yamlContent), 0o644)
}

// SetTUNFd stores the TUN file descriptor from NEPacketTunnelProvider.
func SetTUNFd(fd int32) error {
	if fd < 0 {
		return fmt.Errorf("invalid tun fd: %d", fd)
	}
	mu.Lock()
	tunFdGlobal = fd
	mu.Unlock()
	return nil
}

// ConfigureTUNPath selects runtime TUN options for real utun vs socketpair fallback.
// socketPair=true  → packetFlow bridge (primary on modern iOS).
// socketPair=false → BaoLianDeng-style utun fd.
func ConfigureTUNPath(socketPair bool) {
	mu.Lock()
	tunIsSocketPair = socketPair
	mu.Unlock()
}

// StartWithExternalController starts Mihomo with REST API enabled.
func StartWithExternalController(addr, secret string) error {
	mu.Lock()
	defer mu.Unlock()
	if running {
		return fmt.Errorf("proxy already running")
	}

	cfg, err := executor.Parse()
	if err != nil {
		return fmt.Errorf("parse config: %w", err)
	}
	runtime.GC()
	debug.FreeOSMemory()

	cfg.General.FindProcessMode = process.FindProcessMode(process.FindProcessOff)
	cfg.Controller.ExternalController = addr
	cfg.Controller.Secret = secret

	// Force usable DNS listen — binding 198.18.0.2 fails on iOS.
	if cfg.DNS != nil {
		cfg.DNS.Listen = "127.0.0.1:1053"
		cfg.DNS.Enable = true
	}

	// Bind ALL dials to physical NIC (IP_BOUND_IF). Never let traffic re-enter utun.
	bindIF := outboundInterfaceName
	if bindIF != "" {
		cfg.General.Interface = bindIF
	}

	if tunFdGlobal >= 0 {
		cfg.General.Tun.Enable = true
		cfg.General.Tun.FileDescriptor = int(tunFdGlobal)
		cfg.General.Tun.AutoRoute = false
		cfg.General.Tun.AutoDetectInterface = false
		cfg.General.Tun.StrictRoute = false
		cfg.General.Tun.Inet6Address = nil
		cfg.General.Tun.DNSHijack = []string{"any:53", "tcp://any:53"}
		cfg.General.Tun.Device = ""
		cfg.General.Tun.MTU = 1400
		if prefix, err := netip.ParsePrefix("198.18.0.1/16"); err == nil {
			cfg.General.Tun.Inet4Address = []netip.Prefix{prefix}
		}
		// RecvMsgX sets UTUN_OPT — invalid on socketpair/injected fd.
		cfg.General.Tun.RecvMsgX = false
		cfg.General.Tun.SendMsgX = false
		// packetFlow bridge: IP packets never hit kernel tcpListener; gVisor handles TCP in userspace.
		cfg.General.Tun.Stack = constant.TunGvisor
		dnsListen := ""
		if cfg.DNS != nil {
			dnsListen = cfg.DNS.Listen
		}
		log.Infoln("BashX TUN fd=%d socketpair=%v stack=%s bindIF=%q recvmsgx=%v dns=%s",
			tunFdGlobal, tunIsSocketPair, cfg.General.Tun.Stack, bindIF,
			cfg.General.Tun.RecvMsgX, dnsListen)
	} else {
		cfg.General.Tun.Enable = false
		log.Infoln("BashX proxy-only mixed-port=%d bindIF=%q (no TUN capture)",
			cfg.General.MixedPort, bindIF)
	}

	var applyErr error
	func() {
		defer func() {
			if r := recover(); r != nil {
				applyErr = fmt.Errorf("apply config panic: %v", r)
			}
		}()
		hub.ApplyConfig(cfg)
	}()
	if applyErr != nil {
		return applyErr
	}
	runtime.GC()
	debug.FreeOSMemory()
	running = true
	log.Infoln("BashX mihomo started controller=%s", addr)
	return nil
}

// StopProxy shuts down the engine.
func StopProxy() {
	mu.Lock()
	defer mu.Unlock()
	if !running {
		return
	}
	executor.Shutdown()
	running = false
	tunFdGlobal = -1
	tunIsSocketPair = false
	outboundInterfaceName = ""
	runtime.GC()
	debug.FreeOSMemory()
}

// IsRunning reports engine state.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

// ValidateConfig validates YAML without applying it.
func ValidateConfig(yamlContent string) error {
	_, err := config.Parse([]byte(yamlContent))
	return err
}

// GetUploadTraffic returns upload bytes.
func GetUploadTraffic() int64 {
	return statistic.DefaultManager.Snapshot().UploadTotal
}

// GetDownloadTraffic returns download bytes.
func GetDownloadTraffic() int64 {
	return statistic.DefaultManager.Snapshot().DownloadTotal
}

// ForceGC triggers GC for Network Extension memory budget.
func ForceGC() {
	runtime.GC()
	debug.FreeOSMemory()
}

// Version returns core version string.
func Version() string {
	return constant.Version
}

// UpdateLogLevel sets mihomo log level.
func UpdateLogLevel(level string) {
	if v, ok := log.LogLevelMapping[level]; ok {
		log.SetLevel(v)
	}
}

// TestDirectTCP dials via physical NIC (IP_BOUND_IF) — same as mihomo egress under VPN.
func TestDirectTCP(host string, port int32) string {
	addr := net.JoinHostPort(host, fmt.Sprintf("%d", port))
	start := time.Now()
	dialer := &net.Dialer{Timeout: 5 * time.Second}
	bindIF := outboundInterfaceName
	if bindIF != "" {
		finder := control.NewDefaultInterfaceFinder()
		dialer.Control = control.BindToInterface(finder, bindIF, -1)
	}
	conn, err := dialer.Dial("tcp", addr)
	elapsed := time.Since(start)
	if err != nil {
		tag := bindIF
		if tag == "" {
			tag = "(none)"
		}
		return fmt.Sprintf("FAIL bindIF=%s after %v: %v", tag, elapsed, err)
	}
	_ = conn.Close()
	return fmt.Sprintf("OK bindIF=%s connected %s in %v", bindIF, addr, elapsed)
}

// TestDNSResolver sends a minimal A query to mihomo DNS listen address.
func TestDNSResolver(dnsAddr string) string {
	conn, err := net.DialTimeout("udp", dnsAddr, 3*time.Second)
	if err != nil {
		return fmt.Sprintf("FAIL connect %s: %v", dnsAddr, err)
	}
	defer conn.Close()

	// Query www.baidu.com A
	q := []byte{
		0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		3, 'w', 'w', 'w', 5, 'b', 'a', 'i', 'd', 'u', 3, 'c', 'o', 'm', 0,
		0x00, 0x01, 0x00, 0x01,
	}
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write(q); err != nil {
		return fmt.Sprintf("FAIL write: %v", err)
	}
	buf := make([]byte, 512)
	n, err := conn.Read(buf)
	if err != nil {
		return fmt.Sprintf("FAIL read: %v", err)
	}
	ip := parseDNSResponseA(buf[:n])
	if ip == "" {
		return fmt.Sprintf("FAIL parse (%d bytes)", n)
	}
	if strings.HasPrefix(ip, "198.18.") {
		return fmt.Sprintf("OK fake-ip %s", ip)
	}
	return fmt.Sprintf("OK ip %s", ip)
}

func parseDNSResponseA(msg []byte) string {
	if len(msg) < 12 {
		return ""
	}
	pos := 12
	qd := int(msg[4])<<8 | int(msg[5])
	for i := 0; i < qd && pos < len(msg); i++ {
		for pos < len(msg) {
			l := int(msg[pos])
			pos++
			if l == 0 {
				break
			}
			if l >= 0xC0 {
				pos++
				break
			}
			pos += l
		}
		pos += 4
	}
	an := int(msg[6])<<8 | int(msg[7])
	for i := 0; i < an && pos < len(msg); i++ {
		if pos < len(msg) && msg[pos] >= 0xC0 {
			pos += 2
		} else {
			for pos < len(msg) {
				l := int(msg[pos])
				pos++
				if l == 0 {
					break
				}
				pos += l
			}
		}
		if pos+10 > len(msg) {
			break
		}
		rtype := int(msg[pos])<<8 | int(msg[pos+1])
		rdlen := int(msg[pos+8])<<8 | int(msg[pos+9])
		pos += 10
		if rtype == 1 && rdlen == 4 && pos+4 <= len(msg) {
			return fmt.Sprintf("%d.%d.%d.%d", msg[pos], msg[pos+1], msg[pos+2], msg[pos+3])
		}
		pos += rdlen
	}
	return ""
}
