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
];

FontCatalogEntry? fontCatalogById(String id) {
  for (final entry in fontCatalog) {
    if (entry.id == id) {
      return entry;
    }
  }
  return null;
}