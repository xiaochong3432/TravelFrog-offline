from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

t = open(str(PROJECT_ROOT) + "/work/spec/guests-mail-tasks.md", encoding='utf8').read()
print('bytes', len(t.encode('utf8')), 'lines', t.count('\n') + 1)
print('fences', t.count('```'))
print('h1', len(re.findall(r'(?m)^# ', t)), 'h2', len(re.findall(r'(?m)^## ', t)),
      'h3', len(re.findall(r'(?m)^### ', t)), 'h4', len(re.findall(r'(?m)^#### ', t)))
print('tables', len(re.findall(r'(?m)^\|', t)))
