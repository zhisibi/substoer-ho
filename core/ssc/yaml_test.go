package ssc

import "testing"

func TestYAMLToJSON(t *testing.T) {
	cases := map[string]string{
		"a: 1\nb: [x, 2, true, null, 1.5]\nc: {z: 1, a: 2}\n": `{"a":1,"b":["x",2,true,null,1.5],"c":{"z":1,"a":2}}`,
		"base: &b {x: 1, y: 2}\nd:\n  <<: *b\n  y: 3\n":       `{"base":{"x":1,"y":2},"d":{"x":1,"y":3}}`,
		"port: '443'\nn: 0x10\nyes: yes\n":                    `{"port":"443","n":16,"yes":"yes"}`,
		"- {name: SG, server: 1.2.3.4, port: 443}\n":          `[{"name":"SG","server":"1.2.3.4","port":443}]`,
		"": `null`,
	}
	for in, want := range cases {
		got, ok := yamlToJSON(in)
		if !ok || got != want {
			t.Errorf("%q: got %s ok=%v want %s", in, got, ok, want)
		}
	}
	for _, bad := range []string{"t: 2001-12-14t21:59:43.10-05:00\n", "x: .inf\n", "x: !<str> 1\n", "a: [\n"} {
		if _, ok := yamlToJSON(bad); ok {
			t.Errorf("%q should fall back", bad)
		}
	}
}
