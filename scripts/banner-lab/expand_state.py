# Hand-expands `@State private var x: T = v` / `@State private var x = v` into the
# stored State<T> the macro would generate, so the file compiles without the
# SwiftUIMacros plugin that the Command Line Tools do not ship.
import re, sys
src = open(sys.argv[1]).read()
def sub(m):
    indent, name, typ, init = m.group(1), m.group(2), m.group(3), m.group(4)
    if typ is None:
        typ = 'Bool' if init.strip() in ('true', 'false') else None
    decl = f'{indent}private var _{name}: State<{typ}>' + (f' = State(initialValue: {init.strip()})' if init else '')
    acc = f'{indent}private var {name}: {typ} {{ get {{ _{name}.wrappedValue }} nonmutating set {{ _{name}.wrappedValue = newValue }} }}'
    return decl + '\n' + acc
src = re.sub(r'^(\s*)@State private var (\w+)(?:: ([\w.]+))?(?: = (.+))?$', sub, src, flags=re.M)
open(sys.argv[2], 'w').write(src)
