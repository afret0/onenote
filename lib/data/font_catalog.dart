class FontCatalogFile {
  const FontCatalogFile({
    required this.weight,
    required this.fileName,
    this.url = '',
    this.bytes = 0,
    this.zipMember = '',
  });

  final int weight;
  final String fileName;
  final String url;
  final int bytes;
  final String zipMember;
}

class FontCatalogEntry {
  const FontCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.licenseName,
    required this.files,
    this.zipUrl = '',
    this.zipBytes = 0,
    this.licenseUrl = '',
    this.licenseZipMember = '',
  });

  final String id;
  final String name;
  final String description;
  final String licenseName;
  final List<FontCatalogFile> files;
  final String zipUrl;
  final int zipBytes;
  final String licenseUrl;
  final String licenseZipMember;

  bool get isZip => zipUrl.isNotEmpty;

  int get downloadBytes =>
      isZip ? zipBytes : files.fold(0, (sum, f) => sum + f.bytes);

  int get installedBytes => files.fold(0, (sum, f) => sum + f.bytes);
}

const fontCatalog = <FontCatalogEntry>[
  FontCatalogEntry(
    id: 'lxgw-wenkai',
    name: '霞鹜文楷',
    description: '开源楷体，笔记阅读感好（Regular + Medium）',
    licenseName: 'SIL OFL 1.1',
    files: [
      FontCatalogFile(
        weight: 400,
        fileName: 'LXGWWenKai-Regular.ttf',
        url:
            'https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf',
        bytes: 25928940,
      ),
      FontCatalogFile(
        weight: 500,
        fileName: 'LXGWWenKai-Medium.ttf',
        url:
            'https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Medium.ttf',
        bytes: 25800076,
      ),
    ],
    licenseUrl:
        'https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.530/OFL.txt',
  ),
  FontCatalogEntry(
    id: 'source-han-sans-sc',
    name: '思源黑体',
    description: 'Adobe/Google 开源黑体（官方整包下载，安装 Regular/Medium/Bold）',
    licenseName: 'SIL OFL 1.1',
    zipUrl:
        'https://github.com/adobe-fonts/source-han-sans/releases/download/2.005R/09_SourceHanSansSC.zip',
    zipBytes: 95177106,
    licenseZipMember: 'LICENSE.txt',
    files: [
      FontCatalogFile(
        weight: 400,
        fileName: 'SourceHanSansSC-Regular.otf',
        bytes: 16529832,
        zipMember: 'OTF/SimplifiedChinese/SourceHanSansSC-Regular.otf',
      ),
      FontCatalogFile(
        weight: 500,
        fileName: 'SourceHanSansSC-Medium.otf',
        bytes: 16546328,
        zipMember: 'OTF/SimplifiedChinese/SourceHanSansSC-Medium.otf',
      ),
      FontCatalogFile(
        weight: 700,
        fileName: 'SourceHanSansSC-Bold.otf',
        bytes: 16963428,
        zipMember: 'OTF/SimplifiedChinese/SourceHanSansSC-Bold.otf',
      ),
    ],
  ),
  FontCatalogEntry(
    id: 'source-han-serif-sc',
    name: '思源宋体',
    description: 'Adobe 开源宋体，衬线书卷感（官方整包下载，安装 Regular/Medium/Bold）',
    licenseName: 'SIL OFL 1.1',
    zipUrl:
        'https://github.com/adobe-fonts/source-han-serif/releases/download/2.003R/09_SourceHanSerifSC.zip',
    zipBytes: 138632153,
    licenseZipMember: 'LICENSE.txt',
    files: [
      FontCatalogFile(
        weight: 400,
        fileName: 'SourceHanSerifSC-Regular.otf',
        bytes: 24543332,
        zipMember: 'OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf',
      ),
      FontCatalogFile(
        weight: 500,
        fileName: 'SourceHanSerifSC-Medium.otf',
        bytes: 24805580,
        zipMember: 'OTF/SimplifiedChinese/SourceHanSerifSC-Medium.otf',
      ),
      FontCatalogFile(
        weight: 700,
        fileName: 'SourceHanSerifSC-Bold.otf',
        bytes: 25521732,
        zipMember: 'OTF/SimplifiedChinese/SourceHanSerifSC-Bold.otf',
      ),
    ],
  ),
  FontCatalogEntry(
    id: 'zhuque-fangsong',
    name: '朱雀仿宋',
    description: '开源仿宋，公文与书卷气（仅 Regular）',
    licenseName: 'SIL OFL 1.1',
    zipUrl:
        'https://github.com/TrionesType/zhuque/releases/download/v0.212/ZhuqueFangsong-v0.212.zip',
    zipBytes: 5743932,
    licenseUrl:
        'https://raw.githubusercontent.com/TrionesType/zhuque/v0.212/LICENSE.txt',
    files: [
      FontCatalogFile(
        weight: 400,
        fileName: 'ZhuqueFangsong-Regular.ttf',
        bytes: 8824084,
        zipMember: 'ZhuqueFangsong-Regular.ttf',
      ),
    ],
  ),
  FontCatalogEntry(
    id: 'lxgw-wenkai-screen',
    name: '霞鹜文楷屏幕版',
    description: '文楷的屏幕优化版，笔画更贴像素渲染（仅 Regular）',
    licenseName: 'SIL OFL 1.1',
    files: [
      FontCatalogFile(
        weight: 400,
        fileName: 'LXGWWenKaiScreen.ttf',
        url:
            'https://github.com/lxgw/LxgwWenKai-Screen/releases/download/v1.530/LXGWWenKaiScreen.ttf',
        bytes: 26095590,
      ),
    ],
    licenseUrl:
        'https://raw.githubusercontent.com/lxgw/LxgwWenKai-Screen/v1.530/OFL.txt',
  ),
  FontCatalogEntry(
    id: 'maple-mono-cn',
    name: 'Maple Mono 中文',
    description: '开源圆体等宽，含中文（官方整包下载，安装 Regular/Medium/Bold）',
    licenseName: 'SIL OFL 1.1',
    zipUrl:
        'https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-CN.zip',
    zipBytes: 140799242,
    licenseZipMember: 'LICENSE.txt',
    files: [
      FontCatalogFile(
        weight: 400,
        fileName: 'MapleMono-CN-Regular.ttf',
        bytes: 18594640,
        zipMember: 'MapleMono-CN-Regular.ttf',
      ),
      FontCatalogFile(
        weight: 500,
        fileName: 'MapleMono-CN-Medium.ttf',
        bytes: 18584900,
        zipMember: 'MapleMono-CN-Medium.ttf',
      ),
      FontCatalogFile(
        weight: 700,
        fileName: 'MapleMono-CN-Bold.ttf',
        bytes: 18549392,
        zipMember: 'MapleMono-CN-Bold.ttf',
      ),
    ],
  ),
];

FontCatalogEntry? fontCatalogById(String id) {
  for (final entry in fontCatalog) {
    if (entry.id == id) {
      return entry;
    }
  }
  return null;
}