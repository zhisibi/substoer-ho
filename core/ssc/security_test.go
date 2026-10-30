package ssc

import (
	"net/url"
	"strings"
	"testing"
)

func TestRedactPathMasksNestedSubscriptionToken(t *testing.T) {
	u, _ := url.Parse("/download/x?url=https%3A%2F%2Fexample.com%2Fsub%3Ftoken%3Dabc123%26foo%3Dbar&access_token=zzz")
	out := redactPath(u)
	if strings.Contains(out, "abc123") || strings.Contains(out, "zzz") {
		t.Fatalf("token leaked in redacted path: %s", out)
	}
	if !strings.Contains(out, "foo") {
		t.Fatalf("non-sensitive parameter should survive: %s", out)
	}
}

func TestRedactTextMasksSecrets(t *testing.T) {
	in := "fetch https://example.com/sub?token=abc123&x=1 age-secret-key=AGE-SECRET-KEY-1XYZ password=hunter2"
	out := redactText(in)
	for _, leak := range []string{"abc123", "AGE-SECRET-KEY-1XYZ", "hunter2"} {
		if strings.Contains(out, leak) {
			t.Fatalf("secret %q leaked in redacted text: %s", leak, out)
		}
	}
}

func TestValidUpdateURL(t *testing.T) {
	good := []string{
		"https://github.com/zhisibi/substoer-ho/releases/download/substore-latest/manifest.json",
		"https://ghfast.top/https://github.com/zhisibi/substoer-ho/releases/download/x/backend.js",
		"https://objects.githubusercontent.com/github-production-release-asset/1/2",
	}
	for _, u := range good {
		if !validUpdateURL(u) {
			t.Fatalf("expected allowed: %s", u)
		}
	}
	bad := []string{
		"http://github.com/x",                 // plain http
		"https://evil.example.com/backend.js", // unknown host
		"https://github.com.evil.com/x",       // look-alike host
		"ftp://github.com/x",
	}
	for _, u := range bad {
		if validUpdateURL(u) {
			t.Fatalf("expected refused: %s", u)
		}
	}
}
