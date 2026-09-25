const fs = require('node:fs')
const path = require('node:path')
const { createRequire } = require('node:module')

const configPath = path.join(__dirname, '../reg-suit/regconfig.json')
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'))
const core = config.core
const workingDir = path.resolve(process.cwd(), core.workingDir ?? '.reg')
const actualDir = path.join(workingDir, 'actual')
const expectedDir = path.join(workingDir, 'expected')
const diffDir = path.join(workingDir, 'diff')
const screenshotsDir = path.resolve(
  process.cwd(),
  process.env.VRT_SCREENSHOTS_DIR,
)

const callerRequire = createRequire(path.join(process.cwd(), 'package.json'))
const regSuitPackagePath = callerRequire.resolve('reg-suit/package.json')
const regSuitPackage = JSON.parse(fs.readFileSync(regSuitPackagePath, 'utf8'))
const regSuitBin =
  typeof regSuitPackage.bin === 'string'
    ? regSuitPackage.bin
    : regSuitPackage.bin?.['reg-suit']
if (!regSuitBin)
  throw new Error('Could not locate the reg-suit CLI package entry point')
const regSuitCliPath = path.resolve(
  path.dirname(regSuitPackagePath),
  regSuitBin,
)
const regSuitRequire = createRequire(regSuitCliPath)
const regSuitCorePath = regSuitRequire.resolve('reg-suit-core')
// Resolve the comparator through reg-suit-core to reuse the caller's installed version.
const regCliModule = createRequire(regSuitCorePath)('reg-cli')
const compareWithRegCli =
  typeof regCliModule === 'function' ? regCliModule : regCliModule.compare
if (typeof compareWithRegCli !== 'function') {
  throw new Error(
    'The installed reg-cli package does not expose its comparison API',
  )
}

const imageExtensions = ['.png', '.jpg', '.jpeg', '.tiff', '.bmp', '.gif']

function copyImages(from, to) {
  const stats = fs.statSync(from)
  if (stats.isDirectory()) {
    for (const inner of fs.readdirSync(from)) {
      copyImages(path.join(from, inner), path.join(to, inner))
    }
  } else if (
    stats.isFile() &&
    imageExtensions.some((ext) => from.endsWith(ext))
  ) {
    fs.mkdirSync(path.dirname(to), { recursive: true })
    fs.copyFileSync(from, to)
  }
}

async function compare() {
  fs.rmSync(actualDir, { recursive: true, force: true })
  copyImages(screenshotsDir, actualDir)

  const ximgdiff = core.ximgdiff ?? { invocationType: 'cli' }
  const result = await new Promise((resolve, reject) => {
    // Omitting `report` preserves comparison output without creating reg-cli's HTML report.
    const emitter = compareWithRegCli({
      actualDir,
      expectedDir,
      diffDir,
      json: path.join(workingDir, 'out.json'),
      update: false,
      ignoreChange: true,
      urlPrefix: '',
      threshold: core.threshold,
      thresholdRate: core.thresholdRate,
      thresholdPixel: core.thresholdPixel,
      matchingThreshold: core.matchingThreshold ?? 0,
      enableAntialias: core.enableAntialias,
      enableCliAdditionalDetection: ximgdiff.invocationType === 'cli',
      enableClientAdditionalDetection: ximgdiff.invocationType !== 'none',
      concurrency: core.concurrency ?? 4,
    })
    emitter.once('complete', resolve)
    emitter.once('error', reject)
  })

  console.log('Comparison Complete')
  console.log(`Changed items: ${result.failedItems.length}`)
  console.log(`New items: ${result.newItems.length}`)
  console.log(`Deleted items: ${result.deletedItems.length}`)
  console.log(`Passed items: ${result.passedItems.length}`)
}

compare().catch((error) => {
  console.error('An error occurs during compare images:')
  console.error(error)
  process.exitCode = 1
})
