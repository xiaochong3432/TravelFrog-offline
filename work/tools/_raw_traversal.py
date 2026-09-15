import socket, sys
p = int(sys.argv[1])
for target in ["/../index.html", "/..%2findex.html", "/game_evil.html"]:
    s = socket.create_connection(("127.0.0.1", p), timeout=10)
    s.sendall(("GET " + target + " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n").encode())
    data = s.recv(200).decode("latin1").split("\r\n")[0]
    print(f"  {target:26s} -> {data}")
    s.close()
