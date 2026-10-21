package ssc

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"strconv"

	"gopkg.in/yaml.v3"
)

// yamlToJSON parses YAML natively for the backend (__hm_yamlParse). Sub-Store parses whole Clash configs
// (often 10k+ lines of rules) several times per download; the bundled JS parser is far too slow in goja and
// blocked the event loop for tens of seconds on a phone. Mapping key order is preserved (it shows up in the
// generated configs). Returns ok=false to let the JS parser handle anything unusual.
func yamlToJSON(s string) (string, bool) {
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(s), &doc); err != nil {
		return "", false
	}
	var buf bytes.Buffer
	if doc.Kind == 0 {
		return "null", true
	}
	if err := writeNode(&buf, &doc, 0); err != nil {
		return "", false
	}
	return buf.String(), true
}

var errUnsupported = errors.New("unsupported")

type kv struct {
	key string
	val *yaml.Node
}

func writeNode(b *bytes.Buffer, n *yaml.Node, depth int) error {
	if depth > 200 {
		return errUnsupported
	}
	switch n.Kind {
	case yaml.DocumentNode:
		if len(n.Content) == 0 {
			b.WriteString("null")
			return nil
		}
		return writeNode(b, n.Content[0], depth+1)
	case yaml.AliasNode:
		return writeNode(b, n.Alias, depth+1)
	case yaml.SequenceNode:
		b.WriteByte('[')
		for i, c := range n.Content {
			if i > 0 {
				b.WriteByte(',')
			}
			if err := writeNode(b, c, depth+1); err != nil {
				return err
			}
		}
		b.WriteByte(']')
		return nil
	case yaml.MappingNode:
		pairs, err := mappingPairs(n, depth)
		if err != nil {
			return err
		}
		b.WriteByte('{')
		for i, p := range pairs {
			if i > 0 {
				b.WriteByte(',')
			}
			kb, _ := json.Marshal(p.key)
			b.Write(kb)
			b.WriteByte(':')
			if err := writeNode(b, p.val, depth+1); err != nil {
				return err
			}
		}
		b.WriteByte('}')
		return nil
	case yaml.ScalarNode:
		return writeScalar(b, n)
	}
	return errUnsupported
}

// mappingPairs flattens a mapping with YAML merge keys (<<): merged keys take the << position, explicit keys win.
func mappingPairs(n *yaml.Node, depth int) ([]kv, error) {
	var out []kv
	idx := map[string]int{}
	set := func(k string, v *yaml.Node, override bool) {
		if i, ok := idx[k]; ok {
			if override {
				out[i].val = v
			}
			return
		}
		idx[k] = len(out)
		out = append(out, kv{k, v})
	}
	for i := 0; i+1 < len(n.Content); i += 2 {
		k, v := n.Content[i], n.Content[i+1]
		if k.Kind == yaml.ScalarNode && k.Tag == "!!merge" {
			m := v
			if m.Kind == yaml.AliasNode {
				m = m.Alias
			}
			srcs := []*yaml.Node{m}
			if m.Kind == yaml.SequenceNode {
				srcs = m.Content
			}
			for _, src := range srcs {
				if src.Kind == yaml.AliasNode {
					src = src.Alias
				}
				if src.Kind != yaml.MappingNode {
					return nil, errUnsupported
				}
				ps, err := mappingPairs(src, depth+1)
				if err != nil {
					return nil, err
				}
				for _, p := range ps {
					set(p.key, p.val, false)
				}
			}
			continue
		}
		ks, err := keyText(k)
		if err != nil {
			return nil, err
		}
		set(ks, v, true)
	}
	return out, nil
}

func keyText(k *yaml.Node) (string, error) {
	if k.Kind == yaml.AliasNode {
		k = k.Alias
	}
	if k.Kind != yaml.ScalarNode {
		return "", errUnsupported
	}
	switch k.Tag {
	case "!!null":
		return "null", nil
	case "!!str", "!!int", "!!float", "!!bool":
		return k.Value, nil
	}
	return "", errUnsupported
}

func writeScalar(b *bytes.Buffer, n *yaml.Node) error {
	switch n.Tag {
	case "!!str":
		s, _ := json.Marshal(n.Value)
		b.Write(s)
	case "!!null":
		b.WriteString("null")
	case "!!bool":
		var v bool
		if err := n.Decode(&v); err != nil {
			return err
		}
		b.WriteString(strconv.FormatBool(v))
	case "!!int":
		var v int64
		if err := n.Decode(&v); err != nil {
			return errUnsupported
		}
		if v > 1<<53 || v < -(1<<53) {
			return errUnsupported
		}
		b.WriteString(strconv.FormatInt(v, 10))
	case "!!float":
		var v float64
		if err := n.Decode(&v); err != nil {
			return errUnsupported
		}
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return errUnsupported
		}
		f, _ := json.Marshal(v)
		b.Write(f)
	default:
		// timestamps, binary, custom tags (!<str> …): leave the document to the JS parser
		return errUnsupported
	}
	return nil
}
