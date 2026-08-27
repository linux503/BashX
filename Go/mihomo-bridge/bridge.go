// Package bridge exposes a gomobile-compatible API for running Mihomo inside
// an iOS Network Extension. Exported names are prefixed with Bridge by gomobile.
package bridge

import (
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"sync"
	"time"

	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"

	_ "golang.org/x/mobile/bind"
)

var (
	mu          sync.Mutex
	running     bool
	tunFdGlobal int32 = -1
)

func init() {
    debug.SetGCPercent(5)
    debug.SetMemoryLimit(32 * 1024 * 1024)
	runtime.GOMAXPROCS(1)
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

// SetTUNFd stores the utun file descriptor from NEPacketTunnelProvider.
func SetTUNFd(fd int32) error {
	if fd < 0 {
		return fmt.Errorf("invalid tun fd: %d", fd)
	}
	mu.Lock()
	tunFdGlobal = fd
	mu.Unlock()
	return nil
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

	if tunFdGlobal >= 0 {
		cfg.General.Tun.Enable = true
		cfg.General.Tun.FileDescriptor = int(tunFdGlobal)
		cfg.General.Tun.AutoRoute = false
		cfg.General.Tun.AutoDetectInterface = false
		if prefix6, err := netip.ParsePrefix("fdfe:dcba:9876::1/126"); err == nil {
			cfg.General.Tun.Inet6Address = []netip.Prefix{prefix6}
		}
	}

	hub.ApplyConfig(cfg)
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
