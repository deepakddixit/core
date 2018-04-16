<?php

namespace Test\Theme;

use OC\Theme\ThemeService;
use OC\Helper\EnvironmentHelper;

class ThemeServiceTest extends \PHPUnit\Framework\TestCase {

	public function testCreatesThemeByGivenName() {
		$themeService = new ThemeService(
			'theme-name',
			\OC::$server->getAppManager(),
			new EnvironmentHelper()
		);
		$theme = $themeService->getTheme();
		$this->assertEquals('theme-name', $theme->getName());
		$this->assertEquals('themes/theme-name', $theme->getDirectory());
	}

	public function testCreatesEmptyThemeIfDefaultDoesNotExist() {
		$themeService = $this->getMockBuilder(ThemeService::class)
			->disableOriginalConstructor()
			->setMethods(['defaultThemeExists'])
			->getMock();

		$themeService->expects($this->any())
			->method('defaultThemeExists')
			->willReturn(false);

		$themeService->__construct(
			'',
			\OC::$server->getAppManager(),
			new EnvironmentHelper()
		);
		$theme = $themeService->getTheme();

		$this->assertEquals('', $theme->getName());
		$this->assertEquals('', $theme->getDirectory());
	}

	public function testCreatesDefaultThemeIfItExists() {
		$themeService = $this->getMockBuilder(ThemeService::class)
			->disableOriginalConstructor()
			->setMethods(['defaultThemeExists'])
			->getMock();

		$themeService->expects($this->any())
			->method('defaultThemeExists')
			->willReturn(true);

		$themeService->__construct(
			'',
			\OC::$server->getAppManager(),
			new EnvironmentHelper()
		);
		$theme = $themeService->getTheme();

		$this->assertEquals('default', $theme->getName());
		$this->assertEquals('themes/default', $theme->getDirectory());
	}

	public function testSetAppThemeSetsName() {
		$themeService = new ThemeService(
			'',
			\OC::$server->getAppManager(),
			new EnvironmentHelper()
		);
		$this->assertEmpty($themeService->getTheme()->getName());
		$themeService->setAppTheme('some-app-theme');
		$this->assertEquals('some-app-theme', $themeService->getTheme()->getName());
	}
}
