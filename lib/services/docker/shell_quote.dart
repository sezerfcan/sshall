/// POSIX single-quote escaping for safe interpolation into a remote shell
/// command. Wraps in single quotes and escapes embedded single quotes as '\''.
String shellSingleQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
