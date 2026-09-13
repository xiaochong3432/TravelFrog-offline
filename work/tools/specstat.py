import re

t = open(r'H:\AI\frog\work\spec\guests-mail-tasks.md', encoding='utf8').read()
print('bytes', len(t.encode('utf8')), 'lines', t.count('\n') + 1)
print('fences', t.count('```'))
print('h1', len(re.findall(r'(?m)^# ', t)), 'h2', len(re.findall(r'(?m)^## ', t)),
      'h3', len(re.findall(r'(?m)^### ', t)), 'h4', len(re.findall(r'(?m)^#### ', t)))
print('tables', len(re.findall(r'(?m)^\|', t)))
